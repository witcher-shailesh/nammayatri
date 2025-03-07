{-
 Copyright 2022-23, Juspay India Pvt Ltd

 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License

 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program

 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY

 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of

 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Domain.Action.Dashboard.Fleet.Registration where

import qualified API.Types.UI.DriverOnboardingV2 as DO
import qualified "dashboard-helper-api" Dashboard.ProviderPlatform.Driver as Common
import qualified "dashboard-helper-api" Dashboard.ProviderPlatform.Driver.Registration as Common
import Data.OpenApi (ToSchema)
import qualified Domain.Action.Dashboard.Driver.Registration as DReg
import qualified Domain.Action.UI.DriverOnboarding.Image as Image
import qualified Domain.Action.UI.DriverOnboardingV2 as Registration
import qualified Domain.Action.UI.FleetDriverAssociation as FDA
import qualified Domain.Action.UI.Registration as Registration
import qualified Domain.Types.DocumentVerificationConfig as DVC
import Domain.Types.FleetOwnerInformation as FOI
import qualified Domain.Types.Merchant as DM
import qualified Domain.Types.Merchant as DMerchant
import qualified Domain.Types.MerchantOperatingCity as DMOC
import qualified Domain.Types.Person as DP
import Environment
import EulerHS.Prelude hiding (id)
import Kernel.Beam.Functions as B
import Kernel.External.Encryption (getDbHash)
import Kernel.Sms.Config
import qualified Kernel.Storage.Hedis as Redis
import Kernel.Types.APISuccess
import qualified Kernel.Types.Beckn.City as City
import qualified Kernel.Types.Beckn.Context as Context
import Kernel.Types.Common
import Kernel.Types.Id
import Kernel.Utils.Common
import qualified Kernel.Utils.Predicates as P
import Kernel.Utils.Validation
import qualified SharedLogic.DriverOnboarding as DomainRC
import SharedLogic.Merchant (findMerchantByShortId)
import qualified SharedLogic.MessageBuilder as MessageBuilder
import qualified Storage.Cac.TransporterConfig as SCTC
import Storage.CachedQueries.Merchant as QMerchant
import qualified Storage.CachedQueries.Merchant.MerchantOperatingCity as CQMOC
import qualified Storage.Queries.FleetDriverAssociation as QFDV
import qualified Storage.Queries.FleetOwnerInformation as QFOI
import qualified Storage.Queries.Person as QP
import Tools.Error
import Tools.SMS as Sms hiding (Success)

---------------------------------------------------------------------
data FleetOwnerLoginReq = FleetOwnerLoginReq
  { mobileNumber :: Text,
    mobileCountryCode :: Text,
    merchantId :: Text,
    otp :: Maybe Text,
    city :: Context.City
  }
  deriving (Generic, Show, Eq, FromJSON, ToJSON, ToSchema)

data UpdateFleetOwnerReq = UpdateFleetOwnerReq
  { firstName :: Maybe Text,
    lastName :: Maybe Text,
    email :: Maybe Text,
    mobileNumber :: Maybe Text,
    mobileCountryCode :: Maybe Text
  }
  deriving (Generic, Show, Eq, FromJSON, ToJSON, ToSchema)

data FleetOwnerRegisterReq = FleetOwnerRegisterReq
  { firstName :: Text,
    lastName :: Text,
    mobileNumber :: Text,
    mobileCountryCode :: Text,
    merchantId :: Text,
    email :: Maybe Text,
    city :: City.City,
    fleetType :: Maybe FOI.FleetType,
    panNumber :: Maybe Text,
    gstNumber :: Maybe Text,
    panImageId1 :: Maybe Text,
    panImageId2 :: Maybe Text,
    gstCertificateImage :: Maybe Text
  }
  deriving (Generic, Show, Eq, FromJSON, ToJSON, ToSchema)

newtype FleetOwnerRegisterRes = FleetOwnerRegisterRes
  { personId :: Text
  }
  deriving (Generic, Show, Eq, FromJSON, ToJSON, ToSchema)

newtype FleetOwnerVerifyRes = FleetOwnerVerifyRes
  { authToken :: Text
  }
  deriving (Generic, Show, Eq, FromJSON, ToJSON, ToSchema)

fleetOwnerRegister :: FleetOwnerRegisterReq -> Flow FleetOwnerRegisterRes
fleetOwnerRegister req = do
  let merchantId = ShortId req.merchantId
  mobileNumberHash <- getDbHash req.mobileNumber
  deploymentVersion <- asks (.version)
  merchant <-
    QMerchant.findByShortId merchantId
      >>= fromMaybeM (MerchantNotFound merchantId.getShortId)
  merchantOpCityId <- CQMOC.getMerchantOpCityId Nothing merchant (Just req.city)
  let personAuth = buildFleetOwnerAuthReq merchant.id req
  person <-
    QP.findByMobileNumberAndMerchantAndRole req.mobileCountryCode mobileNumberHash merchant.id DP.FLEET_OWNER
      >>= maybe (createFleetOwnerDetails personAuth merchant.id merchantOpCityId True deploymentVersion.getDeploymentVersion req.fleetType req.gstNumber) return
  fork "Creating Pan Info for Fleet Owner" $ do
    createPanInfo person.id merchant.id merchantOpCityId req.panImageId1 req.panImageId2 req.panNumber
  fork "Uploading GST Image" $ do
    whenJust req.gstCertificateImage $ \gstImage -> do
      let req' = Image.ImageValidateRequest {imageType = DVC.GSTCertificate, image = gstImage, rcNumber = Nothing, validationStatus = Nothing, workflowTransactionId = Nothing, vehicleCategory = Nothing}
      image <- Image.validateImage True (person.id, merchant.id, merchantOpCityId) req'
      QFOI.updateGstImageId (Just image.imageId.getId) person.id
  return $ FleetOwnerRegisterRes {personId = person.id.getId}

createFleetOwnerDetails :: Registration.AuthReq -> Id DMerchant.Merchant -> Id DMOC.MerchantOperatingCity -> Bool -> Text -> Maybe FOI.FleetType -> Maybe Text -> Flow DP.Person
createFleetOwnerDetails authReq merchantId merchantOpCityId isDashboard deploymentVersion mbfleetType mbgstNumber = do
  transporterConfig <- SCTC.findByMerchantOpCityId merchantOpCityId Nothing >>= fromMaybeM (TransporterConfigNotFound merchantOpCityId.getId)
  person <- Registration.makePerson authReq transporterConfig Nothing Nothing Nothing Nothing (Just deploymentVersion) merchantId merchantOpCityId isDashboard (Just DP.FLEET_OWNER)
  void $ QP.create person
  createFleetOwnerInfo person.id merchantId mbfleetType mbgstNumber
  pure person

createPanInfo :: Id DP.Person -> Id DMerchant.Merchant -> Id DMOC.MerchantOperatingCity -> Maybe Text -> Maybe Text -> Maybe Text -> Flow ()
createPanInfo personId merchantId merchantOperatingCityId (Just img1) _ (Just panNo) = do
  let req' = Image.ImageValidateRequest {imageType = DVC.PanCard, image = img1, rcNumber = Nothing, validationStatus = Nothing, workflowTransactionId = Nothing, vehicleCategory = Nothing}
  image <- Image.validateImage True (personId, merchantId, merchantOperatingCityId) req'
  let panReq = DO.DriverPanReq {panNumber = panNo, imageId1 = image.imageId, imageId2 = Nothing, consent = True, nameOnCard = Nothing, dateOfBirth = Nothing, consentTimestamp = Nothing, validationStatus = Nothing, verifiedBy = Nothing}
  void $ Registration.postDriverRegisterPancard (Just personId, merchantId, merchantOperatingCityId) panReq
createPanInfo _ _ _ _ _ _ = pure () --------- currently we can have it like this as Pan info is optional

createFleetOwnerInfo :: Id DP.Person -> Id DMerchant.Merchant -> Maybe FOI.FleetType -> Maybe Text -> Flow ()
createFleetOwnerInfo personId merchantId mbFleetType mbGstNumber = do
  now <- getCurrentTime
  let fleetType = fromMaybe NORMAL_FLEET mbFleetType
      fleetOwnerInfo =
        FOI.FleetOwnerInformation
          { fleetOwnerPersonId = personId,
            merchantId = merchantId,
            fleetType = fleetType,
            enabled = True, ------ currently we are not validating any fleet owner Document there fore marking it as true
            blocked = False,
            verified = False,
            gstNumber = mbGstNumber,
            gstImageId = Nothing,
            createdAt = now,
            updatedAt = now
          }
  QFOI.create fleetOwnerInfo

fleetOwnerLogin ::
  FleetOwnerLoginReq ->
  Flow APISuccess
fleetOwnerLogin req = do
  runRequestValidation validateInitiateLoginReq req
  smsCfg <- asks (.smsCfg)
  let mobileNumber = req.mobileNumber
      countryCode = req.mobileCountryCode
  let merchantId = ShortId req.merchantId
  merchant <-
    QMerchant.findByShortId merchantId
      >>= fromMaybeM (MerchantNotFound merchantId.getShortId)
  merchantOpCityId <- CQMOC.getMerchantOpCityId Nothing merchant (Just req.city)
  let useFakeOtpM = useFakeSms smsCfg
  otp <- maybe generateOTPCode (return . show) useFakeOtpM
  whenNothing_ useFakeOtpM $ do
    let otpHash = smsCfg.credConfig.otpHash
    let otpCode = otp
        phoneNumber = countryCode <> mobileNumber
        sender = smsCfg.sender
    withLogTag ("mobileNumber" <> req.mobileNumber) $
      do
        message <-
          MessageBuilder.buildSendOTPMessage merchantOpCityId $
            MessageBuilder.BuildSendOTPMessageReq
              { otp = otpCode,
                hash = otpHash
              }
        Sms.sendSMS merchant.id merchantOpCityId (Sms.SendSMSReq message phoneNumber sender)
        >>= Sms.checkSmsResult
  let key = makeMobileNumberOtpKey mobileNumber
  expTime <- fromIntegral <$> asks (.cacheConfig.configsExpTime)
  Redis.setExp key otp expTime
  pure Success

buildFleetOwnerAuthReq ::
  Id DMerchant.Merchant ->
  FleetOwnerRegisterReq ->
  Registration.AuthReq
buildFleetOwnerAuthReq merchantId' FleetOwnerRegisterReq {..} =
  Registration.AuthReq
    { name = Just (firstName <> " " <> lastName),
      mobileNumber = Just mobileNumber,
      mobileCountryCode = Just mobileCountryCode,
      merchantId = merchantId'.getId,
      merchantOperatingCity = Just city,
      identifierType = Just DP.MOBILENUMBER,
      email = Nothing,
      registrationLat = Nothing,
      registrationLon = Nothing
    }

fleetOwnerVerify ::
  FleetOwnerLoginReq ->
  Flow APISuccess
fleetOwnerVerify req = do
  case req.otp of
    Just otp -> do
      mobileNumberOtpKey <- Redis.safeGet $ makeMobileNumberOtpKey req.mobileNumber
      case mobileNumberOtpKey of
        Just otpHash -> do
          unless (otpHash == otp) $ throwError InvalidAuthData
          let merchantId = ShortId req.merchantId
          merchant <-
            QMerchant.findByShortId merchantId
              >>= fromMaybeM (MerchantNotFound merchantId.getShortId)
          mobileNumberHash <- getDbHash req.mobileNumber
          person <- QP.findByMobileNumberAndMerchantAndRole req.mobileCountryCode mobileNumberHash merchant.id DP.FLEET_OWNER >>= fromMaybeM (PersonNotFound req.mobileNumber)
          void $ QFOI.updateFleetOwnerVerifiedStatus True person.id
          pure Success
        Nothing -> throwError InvalidAuthData
    _ -> throwError InvalidAuthData

makeMobileNumberOtpKey :: Text -> Text
makeMobileNumberOtpKey mobileNumber = "MobileNumberOtp:mobileNumber-" <> mobileNumber

validateInitiateLoginReq :: Validate FleetOwnerLoginReq
validateInitiateLoginReq FleetOwnerLoginReq {..} =
  sequenceA_
    [ validateField "mobileNumber" mobileNumber P.mobileNumber,
      validateField "mobileCountryCode" mobileCountryCode P.mobileCountryCode
    ]

sendFleetJoiningOtp :: ShortId DM.Merchant -> Context.City -> Text -> Common.AuthReq -> Flow Common.AuthRes
sendFleetJoiningOtp merchantShortId opCity fleetOwnerName req = do
  merchant <- findMerchantByShortId merchantShortId
  smsCfg <- asks (.smsCfg)
  merchantOpCityId <- CQMOC.getMerchantOpCityId Nothing merchant (Just opCity)
  mobileNumberHash <- getDbHash req.mobileNumber
  mbPerson <- B.runInReplica $ QP.findByMobileNumberAndMerchantAndRole req.mobileCountryCode mobileNumberHash merchant.id DP.DRIVER
  case mbPerson of
    Nothing -> DReg.auth merchantShortId opCity req -------------- to onboard a driver that is not the part of the fleet
    Just person -> do
      let useFakeOtpM = (show <$> useFakeSms smsCfg) <|> person.useFakeOtp
          phoneNumber = req.mobileCountryCode <> req.mobileNumber
          sender = smsCfg.sender
      otpCode <- maybe generateOTPCode return useFakeOtpM
      withLogTag ("personId_" <> getId person.id) $ do
        message <-
          MessageBuilder.buildFleetJoiningMessage merchantOpCityId $
            MessageBuilder.BuildFleetJoiningMessageReq
              { otp = otpCode,
                fleetOwnerName = fleetOwnerName
              }
        Sms.sendSMS person.merchantId merchantOpCityId (Sms.SendSMSReq message phoneNumber sender)
          >>= Sms.checkSmsResult
        let key = makeFleetDriverOtpKey phoneNumber
        Redis.setExp key otpCode 3600
      pure $ Common.AuthRes {authId = "ALREADY_USING_APPLICATION", attempts = 0}

verifyFleetJoiningOtp :: ShortId DM.Merchant -> Context.City -> Text -> Maybe Text -> Common.VerifyFleetJoiningOtpReq -> Flow APISuccess
verifyFleetJoiningOtp merchantShortId opCity fleetOwnerId mbAuthId req = do
  merchant <- findMerchantByShortId merchantShortId
  mobileNumberHash <- getDbHash req.mobileNumber
  person <- B.runInReplica $ QP.findByMobileNumberAndMerchantAndRole req.mobileCountryCode mobileNumberHash merchant.id DP.DRIVER >>= fromMaybeM (PersonNotFound req.mobileNumber)
  case mbAuthId of
    Just authId -> do
      smsCfg <- asks (.smsCfg)
      merchantOpCityId <- CQMOC.getMerchantOpCityId Nothing merchant (Just opCity)
      fleetOwner <- B.runInReplica $ QP.findById (Id fleetOwnerId :: Id DP.Person) >>= fromMaybeM (InvalidRequest "Fleet Owner not found")
      deviceToken <- fromMaybeM (InvalidRequest "Device Token not found") $ req.deviceToken
      void $ DReg.verify authId True fleetOwnerId Common.AuthVerifyReq {otp = req.otp, deviceToken = deviceToken}
      let phoneNumber = req.mobileCountryCode <> req.mobileNumber
          sender = smsCfg.sender
      withLogTag ("personId_" <> getId person.id) $ do
        message <-
          MessageBuilder.buildFleetJoinAndDownloadAppMessage merchantOpCityId $
            MessageBuilder.BuildDownloadAppMessageReq
              { fleetOwnerName = fleetOwner.firstName
              }
        Sms.sendSMS person.merchantId merchantOpCityId (Sms.SendSMSReq message phoneNumber sender)
          >>= Sms.checkSmsResult
    Nothing -> do
      let key = makeFleetDriverOtpKey (req.mobileCountryCode <> req.mobileNumber)
      otp <- Redis.get key >>= fromMaybeM (InvalidRequest "OTP not found")
      when (otp /= req.otp) $ throwError (InvalidRequest "Invalid OTP")
      checkAssoc <- B.runInReplica $ QFDV.findByDriverIdAndFleetOwnerId person.id fleetOwnerId True
      when (isJust checkAssoc) $ throwError (InvalidRequest "Driver already associated with fleet")
      assoc <- FDA.makeFleetDriverAssociation person.id fleetOwnerId (DomainRC.convertTextToUTC (Just "2099-12-12"))
      QFDV.create assoc
  pure Success

makeFleetDriverOtpKey :: Text -> Text
makeFleetDriverOtpKey phoneNo = "Fleet:Driver:PhoneNo" <> phoneNo
