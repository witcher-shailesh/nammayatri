{-
 Copyright 2022-23, Juspay India Pvt Ltd
 This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License
 as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program
 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of
 the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Domain.Types.FarePolicy.FarePolicyRentalDetails
  ( module Reexport,
    module Domain.Types.FarePolicy.FarePolicyRentalDetails,
  )
where

import Data.Aeson as DA
import Data.List.NonEmpty as NE
import Domain.Types.Common
import qualified Domain.Types.FarePolicy.FarePolicyProgressiveDetails as Domain
import Domain.Types.FarePolicy.FarePolicyRentalDetails.FarePolicyRentalDetailsDistanceBuffer as Reexport
import Kernel.Prelude
import Kernel.Types.Common

data FPRentalDetailsD (s :: UsageSafety) = FPRentalDetails
  { baseFare :: HighPrecMoney,
    perHourCharge :: HighPrecMoney,
    distanceBuffers :: NonEmpty (FPRentalDetailsDistanceBuffersD s),
    perExtraKmRate :: HighPrecMoney,
    perExtraMinRate :: HighPrecMoney,
    includedKmPerHr :: Kilometers,
    plannedPerKmRate :: HighPrecMoney,
    currency :: Currency,
    deadKmFare :: HighPrecMoney,
    maxAdditionalKmsLimit :: Kilometers,
    totalAdditionalKmsLimit :: Kilometers,
    nightShiftCharge :: Maybe Domain.NightShiftCharge,
    waitingChargeInfo :: Maybe Domain.WaitingChargeInfo
  }
  deriving (Generic, Show)

type FPRentalDetails = FPRentalDetailsD 'Safe

instance FromJSON (FPRentalDetailsD 'Unsafe)

instance ToJSON (FPRentalDetailsD 'Unsafe)

-- FIXME remove
instance FromJSON (FPRentalDetailsD 'Safe)

-- FIXME remove
instance ToJSON (FPRentalDetailsD 'Safe)
