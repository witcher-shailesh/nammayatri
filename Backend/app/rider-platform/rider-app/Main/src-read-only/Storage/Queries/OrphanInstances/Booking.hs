{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Storage.Queries.OrphanInstances.Booking where

import qualified Data.Text
import qualified Domain.Types.Booking
import Kernel.Beam.Functions
import Kernel.External.Encryption
import Kernel.Prelude
import qualified Kernel.Prelude
import qualified Kernel.Types.Common
import Kernel.Types.Error
import qualified Kernel.Types.Id
import Kernel.Utils.Common (CacheFlow, EsqDBFlow, MonadFlow, fromMaybeM, getCurrentTime)
import qualified Kernel.Utils.Common
import qualified Kernel.Utils.Version
import qualified Storage.Beam.Booking as Beam
import qualified Storage.Queries.LocationMapping
import Storage.Queries.Transformers.Booking
import qualified Storage.Queries.Transformers.Booking
import qualified Storage.Queries.TripTerms

instance FromTType' Beam.Booking Domain.Types.Booking.Booking where
  fromTType' (Beam.BookingT {..}) = do
    mappings <- Storage.Queries.LocationMapping.findByEntityId id
    fromLocationAndBookingDetails' <- Storage.Queries.Transformers.Booking.fromLocationAndBookingDetails id merchantId merchantOperatingCityId mappings distance fareProductType toLocationId fromLocationId stopLocationId otpCode distanceUnit distanceValue
    backendConfigVersion' <- mapM Kernel.Utils.Version.readVersion (Data.Text.strip <$> backendConfigVersion)
    clientBundleVersion' <- mapM Kernel.Utils.Version.readVersion (Data.Text.strip <$> clientBundleVersion)
    clientConfigVersion' <- mapM Kernel.Utils.Version.readVersion (Data.Text.strip <$> clientConfigVersion)
    clientSdkVersion' <- mapM Kernel.Utils.Version.readVersion (Data.Text.strip <$> clientSdkVersion)
    initialPickupLocation' <- Storage.Queries.Transformers.Booking.getInitialPickupLocation mappings (fst fromLocationAndBookingDetails')
    merchantOperatingCityId' <- Storage.Queries.Transformers.Booking.backfillMOCId merchantOperatingCityId merchantId
    providerUrl' <- parseBaseUrl providerUrl
    tripTerms' <- if isJust tripTermsId then Storage.Queries.TripTerms.findById'' (Kernel.Types.Id.Id (fromJust tripTermsId)) else pure Nothing
    pure $
      Just
        Domain.Types.Booking.Booking
          { backendAppVersion = backendAppVersion,
            backendConfigVersion = backendConfigVersion',
            bookingDetails = snd fromLocationAndBookingDetails',
            bppBookingId = Kernel.Types.Id.Id <$> bppBookingId,
            bppEstimateId = itemId,
            clientBundleVersion = clientBundleVersion',
            clientConfigVersion = clientConfigVersion',
            clientDevice = Kernel.Utils.Version.mkClientDevice clientOsType clientOsVersion,
            clientId = Kernel.Types.Id.Id <$> clientId,
            clientSdkVersion = clientSdkVersion',
            createdAt = createdAt,
            discount = Kernel.Types.Common.mkPrice currency <$> discount,
            distanceUnit = Kernel.Prelude.fromMaybe Kernel.Types.Common.Meter distanceUnit,
            estimatedApplicationFee = Kernel.Types.Common.mkPrice currency <$> estimatedApplicationFee,
            estimatedDistance = Kernel.Utils.Common.mkDistanceWithDefault distanceUnit estimatedDistanceValue <$> estimatedDistance,
            estimatedDuration = estimatedDuration,
            estimatedFare = Kernel.Types.Common.mkPrice currency estimatedFare,
            estimatedTotalFare = Kernel.Types.Common.mkPrice currency estimatedTotalFare,
            fromLocation = fst fromLocationAndBookingDetails',
            fulfillmentId = fulfillmentId,
            id = Kernel.Types.Id.Id id,
            initialPickupLocation = initialPickupLocation',
            isAirConditioned = isAirConditioned,
            isScheduled = fromMaybe False isScheduled,
            merchantId = Kernel.Types.Id.Id merchantId,
            merchantOperatingCityId = merchantOperatingCityId',
            paymentMethodId = paymentMethodId,
            paymentStatus = paymentStatus,
            paymentUrl = paymentUrl,
            primaryExophone = primaryExophone,
            providerId = providerId,
            providerUrl = providerUrl',
            quoteId = Kernel.Types.Id.Id <$> quoteId,
            returnTime = returnTime,
            riderId = Kernel.Types.Id.Id riderId,
            roundTrip = roundTrip,
            serviceTierName = serviceTierName,
            serviceTierShortDesc = serviceTierShortDesc,
            specialLocationName = specialLocationName,
            specialLocationTag = specialLocationTag,
            startTime = startTime,
            status = status,
            transactionId = riderTransactionId,
            tripTerms = tripTerms',
            updatedAt = updatedAt,
            vehicleServiceTierAirConditioned = vehicleServiceTierAirConditioned,
            vehicleServiceTierSeatingCapacity = vehicleServiceTierSeatingCapacity,
            vehicleServiceTierType = vehicleVariant
          }

instance ToTType' Beam.Booking Domain.Types.Booking.Booking where
  toTType' (Domain.Types.Booking.Booking {..}) = do
    let distance = getDistance bookingDetails
    Beam.BookingT
      { Beam.backendAppVersion = backendAppVersion,
        Beam.backendConfigVersion = Kernel.Utils.Version.versionToText <$> backendConfigVersion,
        Beam.distance = Kernel.Utils.Common.distanceToHighPrecMeters <$> distance,
        Beam.fareProductType = getFareProductType bookingDetails,
        Beam.otpCode = getOtpCode bookingDetails,
        Beam.stopLocationId = getStopLocationId bookingDetails,
        Beam.toLocationId = getToLocationId bookingDetails,
        Beam.bppBookingId = Kernel.Types.Id.getId <$> bppBookingId,
        Beam.itemId = bppEstimateId,
        Beam.clientBundleVersion = Kernel.Utils.Version.versionToText <$> clientBundleVersion,
        Beam.clientConfigVersion = Kernel.Utils.Version.versionToText <$> clientConfigVersion,
        Beam.clientOsType = clientDevice <&> (.deviceType),
        Beam.clientOsVersion = clientDevice <&> (.deviceVersion),
        Beam.clientId = Kernel.Types.Id.getId <$> clientId,
        Beam.clientSdkVersion = Kernel.Utils.Version.versionToText <$> clientSdkVersion,
        Beam.createdAt = createdAt,
        Beam.discount = discount <&> (.amount),
        Beam.distanceUnit = Kernel.Prelude.Just distanceUnit,
        Beam.estimatedApplicationFee = estimatedApplicationFee <&> (.amount),
        Beam.distanceValue = Kernel.Utils.Common.distanceToHighPrecDistance distanceUnit <$> distance,
        Beam.estimatedDistance = Kernel.Utils.Common.distanceToHighPrecMeters <$> estimatedDistance,
        Beam.estimatedDistanceValue = Kernel.Utils.Common.distanceToHighPrecDistance distanceUnit <$> estimatedDistance,
        Beam.estimatedDuration = estimatedDuration,
        Beam.currency = Just $ (.currency) estimatedFare,
        Beam.estimatedFare = (.amount) estimatedFare,
        Beam.estimatedTotalFare = (.amount) estimatedTotalFare,
        Beam.fromLocationId = Just $ Kernel.Types.Id.getId $ (.id) fromLocation,
        Beam.fulfillmentId = fulfillmentId,
        Beam.id = Kernel.Types.Id.getId id,
        Beam.isAirConditioned = isAirConditioned,
        Beam.isScheduled = Just isScheduled,
        Beam.merchantId = Kernel.Types.Id.getId merchantId,
        Beam.merchantOperatingCityId = Just $ Kernel.Types.Id.getId merchantOperatingCityId,
        Beam.paymentMethodId = paymentMethodId,
        Beam.paymentStatus = paymentStatus,
        Beam.paymentUrl = paymentUrl,
        Beam.primaryExophone = primaryExophone,
        Beam.providerId = providerId,
        Beam.providerUrl = showBaseUrl providerUrl,
        Beam.quoteId = Kernel.Types.Id.getId <$> quoteId,
        Beam.returnTime = returnTime,
        Beam.riderId = Kernel.Types.Id.getId riderId,
        Beam.roundTrip = roundTrip,
        Beam.serviceTierName = serviceTierName,
        Beam.serviceTierShortDesc = serviceTierShortDesc,
        Beam.specialLocationName = specialLocationName,
        Beam.specialLocationTag = specialLocationTag,
        Beam.startTime = startTime,
        Beam.status = status,
        Beam.riderTransactionId = transactionId,
        Beam.tripTermsId = Kernel.Types.Id.getId <$> (tripTerms <&> (.id)),
        Beam.updatedAt = updatedAt,
        Beam.vehicleServiceTierAirConditioned = vehicleServiceTierAirConditioned,
        Beam.vehicleServiceTierSeatingCapacity = vehicleServiceTierSeatingCapacity,
        Beam.vehicleVariant = vehicleServiceTierType
      }
