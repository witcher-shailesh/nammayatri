{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Domain.Types.VehicleRegistrationCertificate where

import Data.Aeson
import qualified Domain.Types.Image
import qualified Domain.Types.Merchant
import qualified Domain.Types.MerchantOperatingCity
import qualified Domain.Types.Vehicle
import Kernel.External.Encryption
import Kernel.Prelude
import qualified Kernel.Types.Documents
import qualified Kernel.Types.Id
import qualified Tools.Beam.UtilsTH

data VehicleRegistrationCertificateE e = VehicleRegistrationCertificate
  { airConditioned :: Kernel.Prelude.Maybe Kernel.Prelude.Bool,
    certificateNumber :: Kernel.External.Encryption.EncryptedHashedField e Kernel.Prelude.Text,
    dateOfRegistration :: Kernel.Prelude.Maybe Kernel.Prelude.UTCTime,
    documentImageId :: Kernel.Types.Id.Id Domain.Types.Image.Image,
    failedRules :: [Kernel.Prelude.Text],
    fitnessExpiry :: Kernel.Prelude.UTCTime,
    fleetOwnerId :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    id :: Kernel.Types.Id.Id Domain.Types.VehicleRegistrationCertificate.VehicleRegistrationCertificate,
    insuranceValidity :: Kernel.Prelude.Maybe Kernel.Prelude.UTCTime,
    luggageCapacity :: Kernel.Prelude.Maybe Kernel.Prelude.Int,
    manufacturerModel :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    oxygen :: Kernel.Prelude.Maybe Kernel.Prelude.Bool,
    permitExpiry :: Kernel.Prelude.Maybe Kernel.Prelude.UTCTime,
    pucExpiry :: Kernel.Prelude.Maybe Kernel.Prelude.UTCTime,
    rejectReason :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    reviewRequired :: Kernel.Prelude.Maybe Kernel.Prelude.Bool,
    reviewedAt :: Kernel.Prelude.Maybe Kernel.Prelude.UTCTime,
    userPassedVehicleCategory :: Kernel.Prelude.Maybe Domain.Types.Vehicle.Category,
    vehicleCapacity :: Kernel.Prelude.Maybe Kernel.Prelude.Int,
    vehicleClass :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    vehicleColor :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    vehicleDoors :: Kernel.Prelude.Maybe Kernel.Prelude.Int,
    vehicleEnergyType :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    vehicleManufacturer :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    vehicleModel :: Kernel.Prelude.Maybe Kernel.Prelude.Text,
    vehicleModelYear :: Kernel.Prelude.Maybe Kernel.Prelude.Int,
    vehicleRating :: Kernel.Prelude.Maybe Kernel.Prelude.Double,
    vehicleSeatBelts :: Kernel.Prelude.Maybe Kernel.Prelude.Int,
    vehicleVariant :: Kernel.Prelude.Maybe Domain.Types.Vehicle.Variant,
    ventilator :: Kernel.Prelude.Maybe Kernel.Prelude.Bool,
    verificationStatus :: Kernel.Types.Documents.VerificationStatus,
    merchantId :: Kernel.Prelude.Maybe (Kernel.Types.Id.Id Domain.Types.Merchant.Merchant),
    merchantOperatingCityId :: Kernel.Prelude.Maybe (Kernel.Types.Id.Id Domain.Types.MerchantOperatingCity.MerchantOperatingCity),
    createdAt :: Kernel.Prelude.UTCTime,
    updatedAt :: Kernel.Prelude.UTCTime
  }
  deriving (Generic)

type VehicleRegistrationCertificate = VehicleRegistrationCertificateE 'AsEncrypted

type DecryptedVehicleRegistrationCertificate = VehicleRegistrationCertificateE 'AsUnencrypted

instance EncryptedItem VehicleRegistrationCertificate where
  type Unencrypted VehicleRegistrationCertificate = (DecryptedVehicleRegistrationCertificate, HashSalt)
  encryptItem (entity, salt) = do
    certificateNumber_ <- encryptItem (certificateNumber entity, salt)
    pure
      VehicleRegistrationCertificate
        { airConditioned = airConditioned entity,
          certificateNumber = certificateNumber_,
          dateOfRegistration = dateOfRegistration entity,
          documentImageId = documentImageId entity,
          failedRules = failedRules entity,
          fitnessExpiry = fitnessExpiry entity,
          fleetOwnerId = fleetOwnerId entity,
          id = id entity,
          insuranceValidity = insuranceValidity entity,
          luggageCapacity = luggageCapacity entity,
          manufacturerModel = manufacturerModel entity,
          oxygen = oxygen entity,
          permitExpiry = permitExpiry entity,
          pucExpiry = pucExpiry entity,
          rejectReason = rejectReason entity,
          reviewRequired = reviewRequired entity,
          reviewedAt = reviewedAt entity,
          userPassedVehicleCategory = userPassedVehicleCategory entity,
          vehicleCapacity = vehicleCapacity entity,
          vehicleClass = vehicleClass entity,
          vehicleColor = vehicleColor entity,
          vehicleDoors = vehicleDoors entity,
          vehicleEnergyType = vehicleEnergyType entity,
          vehicleManufacturer = vehicleManufacturer entity,
          vehicleModel = vehicleModel entity,
          vehicleModelYear = vehicleModelYear entity,
          vehicleRating = vehicleRating entity,
          vehicleSeatBelts = vehicleSeatBelts entity,
          vehicleVariant = vehicleVariant entity,
          ventilator = ventilator entity,
          verificationStatus = verificationStatus entity,
          merchantId = merchantId entity,
          merchantOperatingCityId = merchantOperatingCityId entity,
          createdAt = createdAt entity,
          updatedAt = updatedAt entity
        }
  decryptItem entity = do
    certificateNumber_ <- fst <$> decryptItem (certificateNumber entity)
    pure
      ( VehicleRegistrationCertificate
          { airConditioned = airConditioned entity,
            certificateNumber = certificateNumber_,
            dateOfRegistration = dateOfRegistration entity,
            documentImageId = documentImageId entity,
            failedRules = failedRules entity,
            fitnessExpiry = fitnessExpiry entity,
            fleetOwnerId = fleetOwnerId entity,
            id = id entity,
            insuranceValidity = insuranceValidity entity,
            luggageCapacity = luggageCapacity entity,
            manufacturerModel = manufacturerModel entity,
            oxygen = oxygen entity,
            permitExpiry = permitExpiry entity,
            pucExpiry = pucExpiry entity,
            rejectReason = rejectReason entity,
            reviewRequired = reviewRequired entity,
            reviewedAt = reviewedAt entity,
            userPassedVehicleCategory = userPassedVehicleCategory entity,
            vehicleCapacity = vehicleCapacity entity,
            vehicleClass = vehicleClass entity,
            vehicleColor = vehicleColor entity,
            vehicleDoors = vehicleDoors entity,
            vehicleEnergyType = vehicleEnergyType entity,
            vehicleManufacturer = vehicleManufacturer entity,
            vehicleModel = vehicleModel entity,
            vehicleModelYear = vehicleModelYear entity,
            vehicleRating = vehicleRating entity,
            vehicleSeatBelts = vehicleSeatBelts entity,
            vehicleVariant = vehicleVariant entity,
            ventilator = ventilator entity,
            verificationStatus = verificationStatus entity,
            merchantId = merchantId entity,
            merchantOperatingCityId = merchantOperatingCityId entity,
            createdAt = createdAt entity,
            updatedAt = updatedAt entity
          },
        ""
      )

instance EncryptedItem' VehicleRegistrationCertificate where
  type UnencryptedItem VehicleRegistrationCertificate = DecryptedVehicleRegistrationCertificate
  toUnencrypted a salt = (a, salt)
  fromUnencrypted = fst
