{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module SharedLogic.DriverOnboarding where

import Control.Applicative ((<|>))
import qualified Data.List as DL
import qualified Data.Text as T
import Data.Time hiding (getCurrentTime)
import qualified Data.Time.Calendar.OrdinalDate as TO
import qualified Domain.Types.DocumentVerificationConfig as DVC
import qualified Domain.Types.DriverInformation as DI
import Domain.Types.DriverRCAssociation
import qualified Domain.Types.DriverStats as DS
import qualified Domain.Types.FleetRCAssociation as FRCA
import qualified Domain.Types.Image as Domain
import qualified Domain.Types.Merchant as DTM
import qualified Domain.Types.MerchantMessage as DMM
import qualified Domain.Types.MerchantOperatingCity as DMOC
import Domain.Types.Person
import qualified Domain.Types.ServiceTierType as DVST
import Domain.Types.Vehicle
import Domain.Types.VehicleRegistrationCertificate
import qualified Domain.Types.VehicleServiceTier as DVST
import Environment
import Kernel.Beam.Functions
import Kernel.External.Encryption
import Kernel.External.Ticket.Interface.Types as Ticket
import Kernel.Prelude
import Kernel.Types.Documents
import qualified Kernel.Types.Documents as Documents
import Kernel.Types.Error
import Kernel.Types.Id
import Kernel.Utils.Common
import qualified SharedLogic.Allocator.Jobs.Overlay.SendOverlay as ACOverlay
import SharedLogic.MessageBuilder (addBroadcastMessageToKafka)
import SharedLogic.VehicleServiceTier
import qualified Storage.Cac.TransporterConfig as SCTC
import qualified Storage.CachedQueries.DocumentVerificationConfig as CQDVC
import qualified Storage.CachedQueries.Merchant as CQM
import qualified Storage.CachedQueries.Merchant.MerchantMessage as QMM
import qualified Storage.CachedQueries.Merchant.MerchantOperatingCity as CQMOC
import qualified Storage.Queries.DriverInformation as DIQuery
import qualified Storage.Queries.Image as Query
import qualified Storage.Queries.Message as MessageQuery
import qualified Storage.Queries.Person as QP
import qualified Storage.Queries.Vehicle as QVehicle
import qualified Storage.Queries.VehicleRegistrationCertificate as QRC
import Tools.Error
import qualified Tools.Ticket as TT
import Tools.Whatsapp as Whatsapp
import Utils.Common.Cac.KeyNameConstants

driverDocumentTypes :: [DVC.DocumentType]
driverDocumentTypes = [DVC.DriverLicense, DVC.AadhaarCard, DVC.PanCard, DVC.Permissions, DVC.ProfilePhoto, DVC.UploadProfile, DVC.SocialSecurityNumber, DVC.BackgroundVerification]

vehicleDocumentTypes :: [DVC.DocumentType]
vehicleDocumentTypes = [DVC.VehicleRegistrationCertificate, DVC.VehiclePermit, DVC.VehicleFitnessCertificate, DVC.VehicleInsurance, DVC.VehiclePUC, DVC.VehicleInspectionForm, DVC.SubscriptionPlan]

notifyErrorToSupport ::
  Person ->
  Id DTM.Merchant ->
  Id DMOC.MerchantOperatingCity ->
  Maybe T.Text ->
  T.Text ->
  [Maybe DriverOnboardingError] ->
  Flow ()
notifyErrorToSupport person merchantId merchantOpCityId driverPhone _ errs = do
  transporterConfig <- SCTC.findByMerchantOpCityId merchantOpCityId (Just (DriverId (cast person.id))) >>= fromMaybeM (TransporterConfigNotFound merchantOpCityId.getId)
  let reasons = catMaybes $ mapMaybe toMsg errs
  let description = T.intercalate ", " reasons
  _ <- TT.createTicket merchantId merchantOpCityId (mkTicket description transporterConfig)
  return ()
  where
    toMsg e = toMessage <$> e

    mkTicket description transporterConfig =
      Ticket.CreateTicketReq
        { category = "GENERAL",
          subCategory = Just "DRIVER ONBOARDING ISSUE",
          disposition = transporterConfig.kaptureDisposition,
          queue = transporterConfig.kaptureQueue,
          issueId = Nothing,
          issueDescription = description,
          mediaFiles = Nothing,
          name = Just $ person.firstName <> " " <> fromMaybe "" person.lastName,
          phoneNo = driverPhone,
          personId = person.id.getId,
          classification = Ticket.DRIVER,
          rideDescription = Nothing
        }

throwImageError :: Id Domain.Image -> DriverOnboardingError -> Flow b
throwImageError id_ err = do
  _ <- Query.addFailureReason (Just err) id_
  throwError err

getFreeTrialDaysLeft :: MonadFlow m => Int -> DI.DriverInformation -> m Int
getFreeTrialDaysLeft freeTrialDays driverInfo = do
  now <- getCurrentTime
  let driverEnablementDay = utctDay (fromMaybe now (driverInfo.enabledAt <|> driverInfo.lastEnabledOn))
  return $ max 0 (freeTrialDays - fromInteger (diffDays (utctDay now) driverEnablementDay))

triggerOnboardingAlertsAndMessages :: Person -> DTM.Merchant -> DMOC.MerchantOperatingCity -> Flow ()
triggerOnboardingAlertsAndMessages driver merchant merchantOperatingCity = do
  fork "Triggering onboarding messages" $ do
    -- broadcast messages
    messages <- MessageQuery.findAllOnboardingMessages merchant merchantOperatingCity
    mapM_ (\msg -> addBroadcastMessageToKafka False msg driver.id) messages

    -- whatsapp message
    mobileNumber <- mapM decrypt driver.mobileNumber >>= fromMaybeM (PersonFieldNotPresent "mobileNumber")
    countryCode <- driver.mobileCountryCode & fromMaybeM (PersonFieldNotPresent "mobileCountryCode")
    let phoneNumber = countryCode <> mobileNumber
    merchantMessage <-
      QMM.findByMerchantOpCityIdAndMessageKey merchantOperatingCity.id DMM.WELCOME_TO_PLATFORM
        >>= fromMaybeM (MerchantMessageNotFound merchantOperatingCity.id.getId (show DMM.WELCOME_TO_PLATFORM))
    let jsonData = merchantMessage.jsonData
    result <- Whatsapp.whatsAppSendMessageWithTemplateIdAPI driver.merchantId merchantOperatingCity.id (Whatsapp.SendWhatsAppMessageWithTemplateIdApIReq phoneNumber merchantMessage.templateId jsonData.var1 jsonData.var2 jsonData.var3 Nothing (Just merchantMessage.containsUrlButton))
    when (result._response.status /= "success") $ throwError (InternalError "Unable to send Whatsapp message via dashboard")

enableAndTriggerOnboardingAlertsAndMessages :: Id DMOC.MerchantOperatingCity -> Id Person -> Bool -> Flow ()
enableAndTriggerOnboardingAlertsAndMessages merchantOpCityId personId verified = do
  driverInfo <- DIQuery.findById (cast personId) >>= fromMaybeM (PersonNotFound personId.getId)
  DIQuery.updateEnabledVerifiedState personId True (Just verified)
  when (not driverInfo.enabled && isNothing driverInfo.enabledAt) $ do
    merchantOpCity <- CQMOC.findById merchantOpCityId >>= fromMaybeM (MerchantOperatingCityNotFound merchantOpCityId.getId)
    merchant <- CQM.findById merchantOpCity.merchantId >>= fromMaybeM (MerchantNotFound merchantOpCity.merchantId.getId)
    person <- QP.findById personId >>= fromMaybeM (PersonNotFound personId.getId)
    triggerOnboardingAlertsAndMessages person merchant merchantOpCity

checkAndUpdateAirConditioned :: Bool -> Bool -> Id Person -> [DVST.VehicleServiceTier] -> Flow ()
checkAndUpdateAirConditioned isDashboard isAirConditioned personId cityVehicleServiceTiers = do
  driverInfo <- runInReplica $ DIQuery.findById personId >>= fromMaybeM DriverInfoNotFound
  vehicle <- runInReplica $ QVehicle.findById personId >>= fromMaybeM (VehicleNotFound personId.getId)
  let serviceTierACThresholds = map (\DVST.VehicleServiceTier {isAirConditioned = _a, ..} -> airConditionedThreshold) (filter (\v -> vehicle.variant `elem` v.allowedVehicleVariant) cityVehicleServiceTiers)

  when (isAirConditioned && not (checkIfACAllowedForDriver driverInfo (catMaybes serviceTierACThresholds))) $ do
    when (driverInfo.acUsageRestrictionType == DI.ToggleNotAllowed) $
      if isDashboard
        then do
          DIQuery.removeAcUsageRestriction (Just 0.0) DI.ToggleNotAllowed (driverInfo.acRestrictionLiftCount + 1) personId
          driver <- QP.findById personId >>= fromMaybeM (PersonNotFound personId.getId)
          fork "Send AC Restriction Lifted Overlay" $ ACOverlay.sendACUsageRestrictionLiftedOverlay driver
        else throwError $ InvalidRequest "AC usage is restricted for the driver, please contact support"
    when (driverInfo.acUsageRestrictionType `elem` [DI.ToggleAllowed, DI.NoRestriction]) $
      DIQuery.updateAcUsageRestrictionAndScore DI.ToggleNotAllowed (Just 0.0) personId
  mbRc <- runInReplica $ QRC.findLastVehicleRCWrapper vehicle.registrationNo
  QVehicle.updateAirConditioned (Just isAirConditioned) personId
  whenJust mbRc $ \rc -> QRC.updateAirConditioned (Just isAirConditioned) rc.id

checkIfACAllowedForDriver :: DI.DriverInformation -> [Double] -> Bool
checkIfACAllowedForDriver driverInfo serviceTierACThresholds = null serviceTierACThresholds || any ((fromMaybe 0 driverInfo.airConditionScore) <=) serviceTierACThresholds

incrementDriverAcUsageRestrictionCount :: [DVST.VehicleServiceTier] -> Id Person -> Flow ()
incrementDriverAcUsageRestrictionCount cityVehicleServiceTiers personId = do
  driverInfo <- DIQuery.findById personId >>= fromMaybeM DriverInfoNotFound
  driver <- QP.findById personId >>= fromMaybeM (PersonNotFound personId.getId)
  let mbMaxACUsageRestrictionThreshold = safeMaximum . mapMaybe (\DVST.VehicleServiceTier {..} -> airConditionedThreshold) $ cityVehicleServiceTiers
  let airConditionScore = (fromMaybe 0 driverInfo.airConditionScore) + 1
  if maybe False (airConditionScore >) mbMaxACUsageRestrictionThreshold
    then do
      let newRestrictionType =
            if driverInfo.acUsageRestrictionType == DI.NoRestriction
              then DI.ToggleAllowed
              else driverInfo.acUsageRestrictionType
      DIQuery.updateAcUsageRestrictionAndScore newRestrictionType (Just airConditionScore) personId
      fork "Send AC Restriction Overlay" $ ACOverlay.sendACUsageRestrictionOverlay driver
    else DIQuery.updateAirConditionScore (Just airConditionScore) personId
  where
    safeMaximum :: Ord a => [a] -> Maybe a
    safeMaximum [] = Nothing
    safeMaximum xs = Just (maximum xs)

makeRCAssociation :: (MonadFlow m) => Id DTM.Merchant -> Id DMOC.MerchantOperatingCity -> Id Person -> Id VehicleRegistrationCertificate -> Maybe UTCTime -> m DriverRCAssociation
makeRCAssociation merchantId merchantOperatingCityId driverId rcId end = do
  id <- generateGUID
  now <- getCurrentTime
  return $
    DriverRCAssociation
      { id,
        driverId,
        rcId,
        associatedOn = now,
        associatedTill = end,
        consent = True,
        consentTimestamp = now,
        isRcActive = False,
        merchantId = Just merchantId,
        merchantOperatingCityId = Just merchantOperatingCityId,
        createdAt = now,
        updatedAt = now
      }

makeFleetRCAssociation :: (MonadFlow m) => Id DTM.Merchant -> Id DMOC.MerchantOperatingCity -> Id Person -> Id VehicleRegistrationCertificate -> Maybe UTCTime -> m FRCA.FleetRCAssociation
makeFleetRCAssociation merchantId merchantOperatingCityId fleetOwnerId rcId end = do
  id <- generateGUID
  now <- getCurrentTime
  return $
    FRCA.FleetRCAssociation
      { id,
        rcId,
        fleetOwnerId,
        associatedOn = now,
        associatedTill = end,
        merchantId = Just merchantId,
        merchantOperatingCityId = Just merchantOperatingCityId,
        createdAt = now,
        updatedAt = now
      }

data VehicleRegistrationCertificateAPIEntity = VehicleRegistrationCertificateAPIEntity
  { certificateNumber :: Text,
    fitnessExpiry :: UTCTime,
    permitExpiry :: Maybe UTCTime,
    pucExpiry :: Maybe UTCTime,
    insuranceValidity :: Maybe UTCTime,
    vehicleClass :: Maybe Text,
    vehicleVariant :: Maybe Variant,
    failedRules :: [Text],
    vehicleManufacturer :: Maybe Text,
    vehicleCapacity :: Maybe Int,
    vehicleModel :: Maybe Text,
    manufacturerModel :: Maybe Text,
    reviewRequired :: Maybe Bool,
    vehicleColor :: Maybe Text,
    vehicleEnergyType :: Maybe Text,
    reviewedAt :: Maybe UTCTime,
    verificationStatus :: VerificationStatus,
    fleetOwnerId :: Maybe Text,
    createdAt :: UTCTime
  }
  deriving (Generic, ToSchema, ToJSON, FromJSON)

makeRCAPIEntity :: VehicleRegistrationCertificate -> Text -> VehicleRegistrationCertificateAPIEntity
makeRCAPIEntity VehicleRegistrationCertificate {..} rcDecrypted =
  VehicleRegistrationCertificateAPIEntity
    { certificateNumber = rcDecrypted,
      ..
    }

makeFullVehicleFromRC :: [DVST.VehicleServiceTier] -> DI.DriverInformation -> Person -> DS.DriverStats -> Id DTM.Merchant -> Text -> VehicleRegistrationCertificate -> Id DMOC.MerchantOperatingCity -> UTCTime -> Vehicle
makeFullVehicleFromRC vehicleServiceTiers driverInfo driver driverStats merchantId_ certificateNumber rc merchantOpCityId now = do
  let vehicle = makeVehicleFromRC driver.id merchantId_ certificateNumber rc merchantOpCityId now
  let availableServiceTiersForDriver = (.serviceTierType) . fst <$> selectVehicleTierForDriverWithUsageRestriction True driverStats driverInfo vehicle vehicleServiceTiers
  addSelectedServiceTiers availableServiceTiersForDriver vehicle
  where
    addSelectedServiceTiers :: [DVST.ServiceTierType] -> Vehicle -> Vehicle
    addSelectedServiceTiers serviceTiers Vehicle {..} = Vehicle {selectedServiceTiers = serviceTiers, ..}

makeVehicleFromRC :: Id Person -> Id DTM.Merchant -> Text -> VehicleRegistrationCertificate -> Id DMOC.MerchantOperatingCity -> UTCTime -> Vehicle
makeVehicleFromRC driverId merchantId certificateNumber rc merchantOpCityId now = do
  Vehicle
    { driverId,
      capacity = rc.vehicleCapacity,
      category = getCategory <$> rc.vehicleVariant,
      make = rc.vehicleManufacturer,
      model = fromMaybe "Unkown" rc.vehicleModel,
      size = Nothing,
      merchantId,
      variant = fromMaybe AUTO_RICKSHAW rc.vehicleVariant,
      color = fromMaybe "Unkown" rc.vehicleColor,
      energyType = rc.vehicleEnergyType,
      registrationNo = certificateNumber,
      registrationCategory = Nothing,
      vehicleClass = fromMaybe "Unkown" rc.vehicleClass,
      merchantOperatingCityId = Just merchantOpCityId,
      vehicleName = Nothing,
      airConditioned = rc.airConditioned,
      oxygen = rc.oxygen,
      ventilator = rc.ventilator,
      luggageCapacity = rc.luggageCapacity,
      vehicleRating = rc.vehicleRating,
      selectedServiceTiers = [],
      createdAt = now,
      updatedAt = now
    }

makeVehicleAPIEntity :: Maybe DVST.ServiceTierType -> Vehicle -> VehicleAPIEntity
makeVehicleAPIEntity serviceTierType Vehicle {..} = VehicleAPIEntity {..}

data CreateRCInput = CreateRCInput
  { registrationNumber :: Maybe Text,
    fitnessUpto :: Maybe UTCTime,
    fleetOwnerId :: Maybe Text,
    vehicleCategory :: Maybe Category,
    documentImageId :: Id Domain.Image,
    vehicleClass :: Maybe Text,
    vehicleClassCategory :: Maybe Text,
    insuranceValidity :: Maybe UTCTime,
    seatingCapacity :: Maybe Int,
    permitValidityUpto :: Maybe UTCTime,
    pucValidityUpto :: Maybe UTCTime,
    manufacturer :: Maybe Text,
    manufacturerModel :: Maybe Text,
    airConditioned :: Maybe Bool,
    oxygen :: Maybe Bool,
    ventilator :: Maybe Bool,
    bodyType :: Maybe Text,
    fuelType :: Maybe Text,
    color :: Maybe Text,
    dateOfRegistration :: Maybe UTCTime,
    vehicleModelYear :: Maybe Int
  }

buildRC :: Id DTM.Merchant -> Id DMOC.MerchantOperatingCity -> CreateRCInput -> Flow (Maybe VehicleRegistrationCertificate)
buildRC merchantId merchantOperatingCityId input = do
  now <- getCurrentTime
  id <- generateGUID
  rCConfigs <- CQDVC.findByMerchantOpCityIdAndDocumentTypeAndCategory merchantOperatingCityId DVC.VehicleRegistrationCertificate (fromMaybe CAR input.vehicleCategory) >>= fromMaybeM (DocumentVerificationConfigNotFound merchantOperatingCityId.getId (show DVC.VehicleRegistrationCertificate))
  mEncryptedRC <- encrypt `mapM` input.registrationNumber
  let mbFitnessEpiry = input.fitnessUpto <|> input.permitValidityUpto <|> Just (UTCTime (TO.fromOrdinalDate 1900 1) 0)
  return $ createRC merchantId merchantOperatingCityId input rCConfigs id now <$> mEncryptedRC <*> mbFitnessEpiry

createRC ::
  Id DTM.Merchant ->
  Id DMOC.MerchantOperatingCity ->
  CreateRCInput ->
  DVC.DocumentVerificationConfig ->
  Id VehicleRegistrationCertificate ->
  UTCTime ->
  EncryptedHashedField 'AsEncrypted Text ->
  UTCTime ->
  VehicleRegistrationCertificate
createRC merchantId merchantOperatingCityId input rcconfigs id now certificateNumber expiry = do
  let (verificationStatus, reviewRequired, variant, mbVehicleModel) = validateRCStatus input rcconfigs now expiry
  VehicleRegistrationCertificate
    { id,
      documentImageId = input.documentImageId,
      certificateNumber,
      fitnessExpiry = expiry,
      permitExpiry = input.permitValidityUpto,
      pucExpiry = input.pucValidityUpto,
      vehicleClass = input.vehicleClass,
      vehicleVariant = variant,
      vehicleManufacturer = input.manufacturer <|> input.manufacturerModel,
      vehicleCapacity = input.seatingCapacity,
      vehicleModel = mbVehicleModel,
      vehicleColor = input.color,
      vehicleDoors = Nothing,
      vehicleSeatBelts = Nothing,
      manufacturerModel = input.manufacturerModel,
      vehicleEnergyType = input.fuelType,
      reviewedAt = Nothing,
      reviewRequired,
      insuranceValidity = input.insuranceValidity,
      verificationStatus,
      fleetOwnerId = input.fleetOwnerId,
      merchantId = Just merchantId,
      merchantOperatingCityId = Just merchantOperatingCityId,
      userPassedVehicleCategory = input.vehicleCategory,
      airConditioned = input.airConditioned,
      oxygen = input.oxygen,
      ventilator = input.ventilator,
      luggageCapacity = Nothing,
      vehicleRating = Nothing,
      failedRules = [],
      dateOfRegistration = input.dateOfRegistration,
      vehicleModelYear = input.vehicleModelYear,
      rejectReason = Nothing,
      createdAt = now,
      updatedAt = now
    }

validateRCStatus :: CreateRCInput -> DVC.DocumentVerificationConfig -> UTCTime -> UTCTime -> (Documents.VerificationStatus, Maybe Bool, Maybe Variant, Maybe Text)
validateRCStatus input rcconfigs now expiry = do
  case rcconfigs.supportedVehicleClasses of
    DVC.RCValidClasses [] -> (Documents.INVALID, Nothing, Nothing, Nothing)
    DVC.RCValidClasses vehicleClassVariantMap -> do
      let validCOVsCheck = rcconfigs.vehicleClassCheckType
      let (isCOVValid, reviewRequired, variant, mbVehicleModel) = maybe (False, Nothing, Nothing, Nothing) (isValidCOVRC input.airConditioned input.oxygen input.ventilator input.vehicleClassCategory input.seatingCapacity input.manufacturer input.bodyType input.manufacturerModel vehicleClassVariantMap validCOVsCheck) (input.vehicleClass <|> input.vehicleClassCategory)
      let validInsurance = True -- (not rcInsurenceConfigs.checkExpiry) || maybe False (now <) insuranceValidity
      if ((not rcconfigs.checkExpiry) || now < expiry) && isCOVValid && validInsurance then (Documents.VALID, reviewRequired, variant, mbVehicleModel) else (Documents.INVALID, reviewRequired, variant, mbVehicleModel)
    _ -> (Documents.INVALID, Nothing, Nothing, Nothing)

isValidCOVRC :: Maybe Bool -> Maybe Bool -> Maybe Bool -> Maybe Text -> Maybe Int -> Maybe Text -> Maybe Text -> Maybe Text -> [DVC.VehicleClassVariantMap] -> DVC.VehicleClassCheckType -> Text -> (Bool, Maybe Bool, Maybe Variant, Maybe Text)
isValidCOVRC mbAirConditioned mbOxygen mbVentilator mVehicleCategory capacity manufacturer bodyType manufacturerModel vehicleClassVariantMap validCOVsCheck cov = do
  let sortedVariantMap = sortMaybe vehicleClassVariantMap
  let vehicleClassVariant = DL.find checkIfMatch sortedVariantMap
  case vehicleClassVariant of
    Just obj -> (True, obj.reviewRequired, Just obj.vehicleVariant, obj.vehicleModel)
    Nothing -> (False, Nothing, Nothing, Nothing)
  where
    checkIfMatch obj = do
      let classMatched = classCheckFunction validCOVsCheck (T.toUpper obj.vehicleClass) (T.toUpper cov)
      let categoryMatched = maybe False (classCheckFunction validCOVsCheck (T.toUpper obj.vehicleClass) . T.toUpper) mVehicleCategory
      let capacityMatched = capacityCheckFunction obj.vehicleCapacity capacity
      let manufacturerMatched = manufacturerCheckFunction obj.manufacturer manufacturer
      let manufacturerModelMatched = manufacturerModelCheckFunction obj.manufacturerModel manufacturerModel
      let bodyTypeMatched = bodyTypeCheckFunction obj.bodyType bodyType
      let ambulanceMatched = if obj.vehicleVariant `elem` ambulanceVariants then checkAmbulanceVariant obj.vehicleVariant else ensureNonAmbulance bodyType manufacturerModel
      (classMatched || categoryMatched) && capacityMatched && manufacturerMatched && manufacturerModelMatched && bodyTypeMatched && ambulanceMatched

    ambulanceVariants = [AMBULANCE_TAXI, AMBULANCE_TAXI_OXY, AMBULANCE_AC, AMBULANCE_AC_OXY, AMBULANCE_VENTILATOR] -- Todo: Create a fn to get variants by category
    checkAmbulanceVariant variant = case (mbAirConditioned, mbOxygen, mbVentilator) of
      (_, _, Just True) -> variant == AMBULANCE_VENTILATOR
      (Just True, Just True, _) -> variant == AMBULANCE_AC_OXY
      (Just True, _, _) -> variant == AMBULANCE_AC
      (Just False, Just True, _) -> variant == AMBULANCE_TAXI_OXY
      _ -> variant == AMBULANCE_TAXI

    ensureNonAmbulance bodyType_ manufacturerModel_ = do
      let checkerLiteral = Just "AMBULANCE"
      case (bodyType_, manufacturerModel_) of
        (Nothing, Nothing) -> True
        (Just bt, Nothing) -> not $ bodyTypeCheckFunction checkerLiteral (Just bt)
        (Nothing, Just mfg) -> not $ manufacturerModelCheckFunction checkerLiteral (Just mfg)
        (Just bt, Just mfg) -> not (bodyTypeCheckFunction checkerLiteral (Just bt) || manufacturerModelCheckFunction checkerLiteral (Just mfg))

-- capacityCheckFunction validCapacity rcCapacity
capacityCheckFunction :: Maybe Int -> Maybe Int -> Bool
capacityCheckFunction (Just a) (Just b) = a == b
capacityCheckFunction Nothing (Just _) = True
capacityCheckFunction Nothing Nothing = True
capacityCheckFunction _ _ = False

manufacturerCheckFunction :: Maybe Text -> Maybe Text -> Bool
manufacturerCheckFunction (Just a) (Just b) = T.isInfixOf (T.toUpper a) (T.toUpper b)
manufacturerCheckFunction Nothing (Just _) = True
manufacturerCheckFunction Nothing Nothing = True
manufacturerCheckFunction _ _ = False

manufacturerModelCheckFunction :: Maybe Text -> Maybe Text -> Bool
manufacturerModelCheckFunction (Just a) (Just b) = T.isInfixOf (T.toUpper a) (T.toUpper b)
manufacturerModelCheckFunction Nothing (Just _) = True
manufacturerModelCheckFunction Nothing Nothing = True
manufacturerModelCheckFunction _ _ = False

bodyTypeCheckFunction :: Maybe Text -> Maybe Text -> Bool
bodyTypeCheckFunction (Just a) (Just b) = T.isInfixOf (T.toUpper a) (T.toUpper b)
bodyTypeCheckFunction Nothing (Just _) = True
bodyTypeCheckFunction Nothing Nothing = True
bodyTypeCheckFunction _ _ = False

classCheckFunction :: DVC.VehicleClassCheckType -> Text -> Text -> Bool
classCheckFunction validCOVsCheck =
  case validCOVsCheck of
    DVC.Infix -> T.isInfixOf
    DVC.Prefix -> T.isPrefixOf
    DVC.Suffix -> T.isSuffixOf

compareMaybe :: Ord a => Maybe a -> Maybe a -> Ordering
compareMaybe Nothing Nothing = EQ
compareMaybe Nothing _ = GT
compareMaybe _ Nothing = LT
compareMaybe (Just x) (Just y) = compare x y

compareVehicles :: DVC.VehicleClassVariantMap -> DVC.VehicleClassVariantMap -> Ordering
compareVehicles a b =
  compareMaybe a.priority b.priority
    `mappend` compareMaybe a.manufacturer b.manufacturer
    `mappend` compareMaybe a.manufacturerModel b.manufacturerModel
    `mappend` compareMaybe a.vehicleCapacity b.vehicleCapacity

-- Function to sort list of Maybe values
sortMaybe :: [DVC.VehicleClassVariantMap] -> [DVC.VehicleClassVariantMap]
sortMaybe = DL.sortBy compareVehicles

removeSpaceAndDash :: Text -> Text
removeSpaceAndDash = T.replace "-" "" . T.replace " " ""

convertTextToUTC :: Maybe Text -> Maybe UTCTime
convertTextToUTC a = do
  a_ <- a
  parseTimeM True defaultTimeLocale "%Y-%-m-%-d" $ T.unpack a_

convertUTCTimetoDate :: UTCTime -> Text
convertUTCTimetoDate utctime = T.pack (formatTime defaultTimeLocale "%d/%m/%Y" utctime)

getCategory :: Variant -> Category
getCategory SEDAN = CAR
getCategory SUV = CAR
getCategory HATCHBACK = CAR
getCategory AUTO_RICKSHAW = AUTO_CATEGORY
getCategory TAXI = CAR
getCategory TAXI_PLUS = CAR
getCategory PREMIUM_SEDAN = CAR
getCategory BLACK = CAR
getCategory BLACK_XL = CAR
getCategory BIKE = MOTORCYCLE
getCategory AMBULANCE_TAXI = AMBULANCE
getCategory AMBULANCE_TAXI_OXY = AMBULANCE
getCategory AMBULANCE_AC = AMBULANCE
getCategory AMBULANCE_AC_OXY = AMBULANCE
getCategory AMBULANCE_VENTILATOR = AMBULANCE
