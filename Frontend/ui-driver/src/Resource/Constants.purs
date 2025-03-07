{-
 
  Copyright 2022-23, Juspay India Pvt Ltd
 
  This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License
 
  as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program
 
  is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 
  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details. You should have received a copy of
 
  the GNU Affero General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
-}

module Resource.Constants where

import Common.Types.App as Common
import Data.Array as DA
import Data.Lens ((^.))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..), split, toLower)
import Data.String (trim)
import Language.Strings (getString)
import Language.Types (STR(..))
import Prelude ((==), (&&), (<>), ($))
import Screens.Types as ST
import Services.API (LocationInfo(..), StopLocation(..), StopLocationAddress(..), TripCategory(..))

type Language =
    {
        name :: String,
        value :: String
    }

getLanguages :: Array Language
getLanguages = 
    [
        {name:"English",value:"EN_US"},
        {name:"ಕನ್ನಡ",value:"KN_IN"},
        {name:"हिन्दी",value :"HI_IN"},
        {name:"தமிழ்",value :"TA_IN"},
        {name:"తెలుగు", value : "TE_IN"}
    ]

decodeAddress :: LocationInfo -> Boolean -> String
decodeAddress ( LocationInfo address) fullAddress =
        if fullAddress then 
             if ( trim (fromMaybe "" address.city) == "" && trim (fromMaybe "" address.area) == "" && trim (fromMaybe "" address.street) == "" && trim (fromMaybe "" address.door) == "" && trim (fromMaybe "" address.building) == "" ) then
                    ((fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
            else if ( trim (fromMaybe "" address.area) == "" && trim (fromMaybe "" address.street) == "" && trim (fromMaybe "" address.door) == "" && trim (fromMaybe "" address.building) == "" ) then
                    ((fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
            else if ( trim (fromMaybe "" address.street) == "" && trim (fromMaybe "" address.door) == "" && trim (fromMaybe "" address.building) == "" ) then
                    ((fromMaybe "" address.area) <> ", " <> (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
            else if ( trim (fromMaybe "" address.door) == "" && trim (fromMaybe "" address.building) == "") then
                    ((fromMaybe "" address.street) <> ", " <> (fromMaybe "" address.area) <> ", " <> (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
            else if ( trim (fromMaybe "" address.door) == "") then
                    ((fromMaybe "" address.building) <> ", " <> (fromMaybe "" address.street) <> ", " <> (fromMaybe "" address.area) <> ", " <> (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
                    else
                    ((fromMaybe "" address.door) <> ", " <> (fromMaybe "" address.building) <> ", " <> (fromMaybe "" address.street) <> ", " <> (fromMaybe "" address.area) <> ", " <> (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
        else 
            if ( trim (fromMaybe "" address.city) == "" && trim (fromMaybe "" address.area) == "" && trim (fromMaybe "" address.street) == ""  ) then
                    (trim (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
            else if ( trim (fromMaybe "" address.area) == "" && trim (fromMaybe "" address.street) == "" ) then
                    (trim (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
            else if ( trim (fromMaybe "" address.street) == "") then
                    (trim (fromMaybe "" address.area) <> ", " <> (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country))
                    else
                    (trim (fromMaybe "" address.street)) <> ", " <> (fromMaybe "" address.area) <> ", " <> (fromMaybe "" address.city) <> ", " <> (fromMaybe "" address.state) <> ", " <> (fromMaybe "" address.country)

decodeShortAddress :: LocationInfo -> String
decodeShortAddress (LocationInfo loc) =
  fromMaybe "" loc.area <> ", " <>
  fromMaybe "" loc.city <> ", " <>
  fromMaybe "" loc.country <> ", " <>
  fromMaybe "" loc.areaCode


tripDatesCount :: Int
tripDatesCount = 15

getPspIcon :: String -> String 
getPspIcon vpa = do
    let handleName = ((split (Pattern "@") (vpa)) DA.!! 1)
    case handleName of 
        Nothing -> "ny_ic_defaultpg"
        Just handle -> case handle of
            "ybl" -> "ny_ic_phonepe"
            "ibl" -> "ny_ic_phonepe"
            "axl" -> "ny_ic_phonepe"
            "okhdfcbank" -> "ny_ic_gpay"
            "okicici" -> "ny_ic_gpay"
            "oksbi" -> "ny_ic_gpay"
            "okaxis" -> "ny_ic_gpay"
            "paytm" -> "ny_ic_paytm"
            "apl" -> "ny_ic_amazonpay"
            "yapl" -> "ny_ic_amazonpay"
            "indus" -> "ny_ic_induspay"
            "upi" -> "ny_ic_bhim"
            _ -> "ny_ic_defaultpg"

waitTimeConstructor :: String -> ST.TimerStatus
waitTimeConstructor key = case key of
  "NoStatus" -> ST.NoStatus
  "Triggered" -> ST.Triggered
  "PostTriggered" -> ST.PostTriggered
  "Scheduled" -> ST.Scheduled
  _ -> ST.NoStatus

transformDocText :: ST.RegisterationStep -> String
transformDocText stage = 
  case stage of
    ST.DRIVING_LICENSE_OPTION -> (getString DRIVING_LICENSE)
    ST.VEHICLE_DETAILS_OPTION -> getString VEHICLE_REGISTERATON_CERTIFICATE
    ST.GRANT_PERMISSION -> getString GRANT_PERMISSIONS
    ST.SUBSCRIPTION_PLAN -> getString $ SUBSCRIPTION_PLAN_STR "SUBSCRIPTION_PLAN_STR"
    ST.PROFILE_PHOTO -> getString PROFILE_PHOTO_STR
    ST.AADHAAR_CARD -> getString AADHAAR_CARD_STR
    ST.PAN_CARD -> getString PAN_CARD_STR
    ST.VEHICLE_PERMIT -> getString VEHICLE_PERMIT_STR
    ST.FITNESS_CERTIFICATE -> getString FITNESS_CERTIFICATE_STR
    ST.VEHICLE_INSURANCE -> getString VEHICLE_INSURANCE_STR
    ST.VEHICLE_PUC -> getString VEHICLE_PUC_STR
    ST.NO_OPTION -> ""

transformToRegisterationStep :: String -> ST.RegisterationStep
transformToRegisterationStep doctype = 
  case doctype of
        "DriverLicense" -> ST.DRIVING_LICENSE_OPTION
        "VehicleRegistrationCertificate" -> ST.VEHICLE_DETAILS_OPTION
        "Permissions" -> ST.GRANT_PERMISSION
        "SubscriptionPlan" -> ST.SUBSCRIPTION_PLAN
        "ProfilePhoto" -> ST.PROFILE_PHOTO
        "AadhaarCard" -> ST.AADHAAR_CARD
        "PanCard" -> ST.PAN_CARD
        "VehiclePermit" -> ST.VEHICLE_PERMIT
        "VehicleFitnessCertificate" -> ST.FITNESS_CERTIFICATE
        "VehicleInsurance" -> ST.VEHICLE_INSURANCE
        "VehiclePUC" -> ST.VEHICLE_PUC
        _ -> ST.NO_OPTION

transformToDoctype :: ST.RegisterationStep -> String
transformToDoctype step = 
  case step of
    ST.DRIVING_LICENSE_OPTION -> "DriverLicense"
    ST.VEHICLE_DETAILS_OPTION -> "VehicleRegistrationCertificate"
    ST.VEHICLE_PERMIT -> "VehiclePermit"
    ST.FITNESS_CERTIFICATE -> "VehicleFitnessCertificate"
    ST.VEHICLE_INSURANCE -> "VehicleInsurance"
    ST.VEHICLE_PUC -> "VehiclePUC"
    ST.SUBSCRIPTION_PLAN -> "SubscriptionPlan"
    ST.PROFILE_PHOTO -> "ProfilePhoto"
    ST.AADHAAR_CARD -> "AadhaarCard"
    ST.PAN_CARD -> "PanCard"
    ST.GRANT_PERMISSION -> "Permissions"
    ST.NO_OPTION -> ""

transformVehicleType :: Maybe String -> Maybe ST.VehicleCategory
transformVehicleType vehicletype =
  case vehicletype of
     Just "CAR" -> Just ST.CarCategory
     Just "AUTO_CATEGORY" -> Just ST.AutoCategory
     _ -> Nothing

decodeVehicleType :: String -> Maybe ST.VehicleCategory
decodeVehicleType value = case value of
  "AutoCategory" -> Just ST.AutoCategory
  "CarCategory" -> Just ST.CarCategory
  _ -> Nothing
rideTypeConstructor :: Maybe TripCategory -> ST.TripType
rideTypeConstructor ( tripCategory) = 
        case tripCategory of
            Nothing -> ST.OneWay
            Just (TripCategory tripCategory') ->
                case toLower tripCategory'.tag of
                        "oneway" -> ST.OneWay 
                        "roundtrip" -> ST.RoundTrip
                        "rental" -> ST.Rental
                        "intercity" -> ST.Intercity
                        "rideshare" -> ST.RideShare
                        _ -> ST.OneWay

constructLocationInfo :: Maybe Number -> Maybe Number -> Maybe LocationInfo
constructLocationInfo (latitude) (longitude) = 
    case latitude,longitude of
        Just latitude',Just longitude' -> 
                Just $ LocationInfo {
                        area :  Just "",
                        state :  Just "",
                        country :  Just "",
                        building :  Just "",
                        door : Just "",
                        street :  Just "",
                        lat : latitude',
                        city :  Just "",
                        areaCode :  Just "",
                        lon : longitude'
                }
        _,_ -> Nothing

getLocationInfoFromStopLocation :: StopLocationAddress -> Number -> Number -> LocationInfo
getLocationInfoFromStopLocation (StopLocationAddress {door, building, street, area, city, state, country, areaCode}) lat lon = 
     LocationInfo 
        {
                area :  area,
                state :  state,
                country :  country,
                building :  building,
                door : door,
                street :  street,
                lat : lat,
                city :  city,
                areaCode :  areaCode,
                lon : lon
        }

getHomeStageFromString :: String -> ST.HomeScreenStage
getHomeStageFromString localStage = 
  case localStage of
        "HomeScreen" -> ST.HomeScreen
        "RideRequested" -> ST.RideRequested
        "RideAccepted" -> ST.RideAccepted
        "RideStarted" -> ST.RideStarted
        "RideCompleted" -> ST.RideCompleted
        "ChatWithCustomer" -> ST.ChatWithCustomer
        _ -> ST.HomeScreen

verifiedVehicleOnly :: Boolean
verifiedVehicleOnly = true

pendingVehicleOnly :: Boolean
pendingVehicleOnly = false

getCategoryFromVariant :: String -> Maybe ST.VehicleCategory -- check here if any new vehicle category is introduced
getCategoryFromVariant variant = case variant of
  "AUTO_RICKSHAW" -> Just ST.AutoCategory
  _ -> Just ST.CarCategory

rideMoreEarnMorePopupStartTime :: String
rideMoreEarnMorePopupStartTime = "07:30:00"

referAndEarnCoinPopupStartTime :: String
referAndEarnCoinPopupStartTime = "07:30:00"

convertCoinToCashPopupStartTime :: String
convertCoinToCashPopupStartTime = "12:30:00"

convertCoinsToCashPopupEndTime :: String
convertCoinsToCashPopupEndTime = "16:30:00"

dayEndTime :: String
dayEndTime = "23:59:59"

serviceTierMapping :: String -> Maybe Boolean -> String
serviceTierMapping tierName acRide = 
  case acRide, tierName of
    Just true, "AC Mini" -> "Mini"
    Just false, "Non-AC Mini" -> "Mini"
    _ , _ -> tierName

defaultSliderDist :: Int
defaultSliderDist = 4