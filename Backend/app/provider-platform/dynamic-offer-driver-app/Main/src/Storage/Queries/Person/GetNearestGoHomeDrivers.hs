module Storage.Queries.Person.GetNearestGoHomeDrivers
  ( getNearestGoHomeDrivers,
    NearestGoHomeDriversResult (..),
    NearestGoHomeDriversReq (..),
  )
where

import qualified Data.HashMap.Strict as HashMap
import qualified Data.List as DL
import Domain.Types.DriverInformation as DriverInfo
import Domain.Types.Merchant
import Domain.Types.Person as Person
import Domain.Types.ServiceTierType as DVST
import Domain.Types.Vehicle as DV
import Domain.Types.VehicleServiceTier as DVST
import Kernel.External.Maps as Maps
import qualified Kernel.External.Notification.FCM.Types as FCM
import Kernel.Prelude
import Kernel.Tools.Metrics.CoreMetrics (CoreMetrics)
import Kernel.Types.Id
import Kernel.Types.Version
import Kernel.Utils.CalculateDistance (distanceBetweenInMeters)
import Kernel.Utils.Common hiding (Value)
import qualified SharedLogic.External.LocationTrackingService.Types as LT
import SharedLogic.VehicleServiceTier
import qualified Storage.Queries.Driver.GoHomeFeature.DriverGoHomeRequest.Internal as Int
import qualified Storage.Queries.DriverInformation.Internal as Int
import qualified Storage.Queries.DriverLocation.Internal as Int
import qualified Storage.Queries.DriverStats as QDriverStats
import qualified Storage.Queries.Person.Internal as Int
import qualified Storage.Queries.Vehicle.Internal as Int

data NearestGoHomeDriversReq = NearestGoHomeDriversReq
  { cityServiceTiers :: [DVST.VehicleServiceTier],
    serviceTiers :: [ServiceTierType],
    fromLocation :: LatLong,
    nearestRadius :: Meters,
    homeRadius :: Meters,
    merchantId :: Id Merchant,
    driverPositionInfoExpiry :: Maybe Seconds,
    isRental :: Bool,
    isInterCity :: Bool
  }

data NearestGoHomeDriversResult = NearestGoHomeDriversResult
  { driverId :: Id Driver,
    driverDeviceToken :: Maybe FCM.FCMRecipientToken,
    language :: Maybe Maps.Language,
    onRide :: Bool,
    distanceToDriver :: Meters,
    variant :: DV.Variant,
    serviceTier :: DVST.ServiceTierType,
    serviceTierDowngradeLevel :: Int,
    isAirConditioned :: Maybe Bool,
    lat :: Double,
    lon :: Double,
    mode :: Maybe DriverInfo.DriverMode,
    clientSdkVersion :: Maybe Version,
    clientBundleVersion :: Maybe Version,
    clientConfigVersion :: Maybe Version,
    clientDevice :: Maybe Device,
    backendConfigVersion :: Maybe Version,
    backendAppVersion :: Maybe Text
  }
  deriving (Generic, Show, HasCoordinates)

getNearestGoHomeDrivers ::
  (MonadFlow m, MonadTime m, LT.HasLocationService m r, CoreMetrics m, CacheFlow m r, EsqDBFlow m r) =>
  NearestGoHomeDriversReq ->
  m [NearestGoHomeDriversResult]
getNearestGoHomeDrivers NearestGoHomeDriversReq {..} = do
  driverLocs <- Int.getDriverLocsWithCond merchantId driverPositionInfoExpiry fromLocation nearestRadius
  driverHomeLocs <- Int.getDriverGoHomeReqNearby (driverLocs <&> (.driverId))
  driverInfos <- Int.getDriverInfosWithCond (driverHomeLocs <&> (.driverId)) True False isRental isInterCity
  vehicle <- Int.getVehicles driverInfos
  drivers <- Int.getDrivers vehicle
  driverStats <- QDriverStats.findAllByDriverIds drivers

  logDebug $ "GetNearestDriver - DLoc:- " <> show (length driverLocs) <> " DInfo:- " <> show (length driverInfos) <> " Vehicles:- " <> show (length vehicle) <> " Drivers:- " <> show (length drivers)
  let res = linkArrayList driverLocs driverInfos vehicle drivers driverStats
  logDebug $ "GetNearestGoHomeDrivers Result:- " <> show (length res)
  return res
  where
    linkArrayList driverLocations driverInformations vehicles persons driverStats =
      let personHashMap = HashMap.fromList $ (\p -> (p.id, p)) <$> persons
          driverInfoHashMap = HashMap.fromList $ (\info -> (info.driverId, info)) <$> driverInformations
          vehicleHashMap = HashMap.fromList $ (\v -> (v.driverId, v)) <$> vehicles
          driverStatsHashMap = HashMap.fromList $ (\stats -> (stats.driverId, stats)) <$> driverStats
       in concat $ mapMaybe (buildFullDriverList personHashMap vehicleHashMap driverInfoHashMap driverStatsHashMap) driverLocations

    buildFullDriverList personHashMap vehicleHashMap driverInfoHashMap driverStatsHashMap location = do
      let driverId' = location.driverId
      person <- HashMap.lookup driverId' personHashMap
      vehicle <- HashMap.lookup driverId' vehicleHashMap
      info <- HashMap.lookup driverId' driverInfoHashMap
      driverStats <- HashMap.lookup driverId' driverStatsHashMap

      let dist = (realToFrac $ distanceBetweenInMeters fromLocation $ LatLong {lat = location.lat, lon = location.lon}) :: Double
      let cityServiceTiersHashMap = HashMap.fromList $ (\vst -> (vst.serviceTierType, vst)) <$> cityServiceTiers
      let mbDefaultServiceTierForDriver = find (\vst -> vehicle.variant `elem` vst.defaultForVehicleVariant) cityServiceTiers
      let availableTiersWithUsageRestriction = selectVehicleTierForDriverWithUsageRestriction False driverStats info vehicle cityServiceTiers
      let ifUsageRestricted = any (\(_, usageRestricted) -> usageRestricted) availableTiersWithUsageRestriction
      let selectedDriverServiceTiers =
            if ifUsageRestricted
              then do
                (.serviceTierType) <$> (map fst $ filter (not . snd) availableTiersWithUsageRestriction) -- no need to check for user selection always send for available tiers
              else do
                DL.intersect vehicle.selectedServiceTiers ((.serviceTierType) <$> (map fst $ filter (not . snd) availableTiersWithUsageRestriction))
      if null serviceTiers
        then Just $ mapMaybe (mkDriverResult mbDefaultServiceTierForDriver person vehicle info dist cityServiceTiersHashMap) selectedDriverServiceTiers
        else do
          Just $
            mapMaybe
              ( \serviceTier -> do
                  if serviceTier `elem` selectedDriverServiceTiers
                    then mkDriverResult mbDefaultServiceTierForDriver person vehicle info dist cityServiceTiersHashMap serviceTier
                    else Nothing
              )
              serviceTiers
      where
        mkDriverResult mbDefaultServiceTierForDriver person vehicle info dist cityServiceTiersHashMap serviceTier = do
          serviceTierInfo <- HashMap.lookup serviceTier cityServiceTiersHashMap
          Just $
            NearestGoHomeDriversResult
              { driverId = cast person.id,
                driverDeviceToken = person.deviceToken,
                language = person.language,
                onRide = info.onRide,
                distanceToDriver = roundToIntegral dist,
                variant = vehicle.variant,
                serviceTier = serviceTier,
                serviceTierDowngradeLevel = maybe 0 (\d -> d.priority - serviceTierInfo.priority) mbDefaultServiceTierForDriver,
                isAirConditioned = serviceTierInfo.isAirConditioned,
                lat = location.lat,
                lon = location.lon,
                mode = info.mode,
                clientSdkVersion = person.clientSdkVersion,
                clientBundleVersion = person.clientBundleVersion,
                clientConfigVersion = person.clientConfigVersion,
                clientDevice = person.clientDevice,
                backendConfigVersion = person.backendConfigVersion,
                backendAppVersion = person.backendAppVersion
              }
