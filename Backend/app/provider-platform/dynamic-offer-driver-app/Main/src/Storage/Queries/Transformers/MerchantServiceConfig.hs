module Storage.Queries.Transformers.MerchantServiceConfig where

import qualified Data.Aeson
import qualified Data.Aeson as A
import qualified Data.Text as T
import qualified Domain.Types.MerchantServiceConfig as Domain
import qualified Kernel.External.AadhaarVerification.Interface as AadhaarVerification
import qualified Kernel.External.BackgroundVerification.Types as BackgroundVerification
import qualified Kernel.External.Call as Call
import qualified Kernel.External.Maps.Interface.Types as Maps
import qualified Kernel.External.Maps.Types as Maps
import qualified Kernel.External.Notification as Notification
import Kernel.External.Notification.Interface.Types as Notification
import qualified Kernel.External.Payment.Interface as Payment
import qualified Kernel.External.SMS.Interface as Sms
import Kernel.External.Ticket.Interface.Types as Ticket
import qualified Kernel.External.Tokenize as Tokenize
import qualified Kernel.External.Verification.Interface as Verification
import qualified Kernel.External.Whatsapp.Interface as Whatsapp
import Kernel.Prelude as P
import Kernel.Types.Common
import Kernel.Types.Error
import Kernel.Utils.Common

getConfigJSON :: Domain.ServiceConfig -> Data.Aeson.Value
getConfigJSON = \case
  Domain.MapsServiceConfig mapsCfg -> case mapsCfg of
    Maps.GoogleConfig cfg -> toJSON cfg
    Maps.OSRMConfig cfg -> toJSON cfg
    Maps.MMIConfig cfg -> toJSON cfg
    Maps.NextBillionConfig cfg -> toJSON cfg
  Domain.SmsServiceConfig smsCfg -> case smsCfg of
    Sms.ExotelSmsConfig cfg -> toJSON cfg
    Sms.MyValueFirstConfig cfg -> toJSON cfg
    Sms.GupShupConfig cfg -> toJSON cfg
  Domain.WhatsappServiceConfig whatsappCfg -> case whatsappCfg of
    Whatsapp.GupShupConfig cfg -> toJSON cfg
  Domain.VerificationServiceConfig verificationCfg -> case verificationCfg of
    Verification.IdfyConfig cfg -> toJSON cfg
    Verification.FaceVerificationConfig cfg -> toJSON cfg
    Verification.GovtDataConfig -> toJSON (A.object [])
  Domain.DriverBackgroundVerificationServiceConfig driverBackgroundVerificationCfg -> case driverBackgroundVerificationCfg of
    Verification.SafetyPortalConfig cfg -> toJSON cfg
  Domain.CallServiceConfig callCfg -> case callCfg of
    Call.ExotelConfig cfg -> toJSON cfg
  Domain.AadhaarVerificationServiceConfig aadhaarVerificationCfg -> case aadhaarVerificationCfg of
    AadhaarVerification.GridlineConfig cfg -> toJSON cfg
  Domain.PaymentServiceConfig paymentCfg -> case paymentCfg of
    Payment.JuspayConfig cfg -> toJSON cfg
    Payment.StripeConfig cfg -> toJSON cfg
  Domain.RentalPaymentServiceConfig paymentCfg -> case paymentCfg of
    Payment.JuspayConfig cfg -> toJSON cfg
    Payment.StripeConfig cfg -> toJSON cfg
  Domain.IssueTicketServiceConfig ticketCfg -> case ticketCfg of
    Ticket.KaptureConfig cfg -> toJSON cfg
  Domain.NotificationServiceConfig notificationServiceCfg -> case notificationServiceCfg of
    Notification.FCMConfig cfg -> toJSON cfg
    Notification.PayTMConfig cfg -> toJSON cfg
    Notification.GRPCConfig cfg -> toJSON cfg
  Domain.TokenizationServiceConfig tokenizationCfg -> case tokenizationCfg of
    Tokenize.HyperVergeTokenizationServiceConfig cfg -> toJSON cfg
  Domain.BackgroundVerificationServiceConfig backgroundVerificationCfg -> case backgroundVerificationCfg of
    BackgroundVerification.CheckrConfig cfg -> toJSON cfg

getServiceName :: Domain.ServiceConfig -> Domain.ServiceName
getServiceName = \case
  Domain.MapsServiceConfig mapsCfg -> case mapsCfg of
    Maps.GoogleConfig _ -> Domain.MapsService Maps.Google
    Maps.OSRMConfig _ -> Domain.MapsService Maps.OSRM
    Maps.MMIConfig _ -> Domain.MapsService Maps.MMI
    Maps.NextBillionConfig _ -> Domain.MapsService Maps.NextBillion
  Domain.SmsServiceConfig smsCfg -> case smsCfg of
    Sms.ExotelSmsConfig _ -> Domain.SmsService Sms.ExotelSms
    Sms.MyValueFirstConfig _ -> Domain.SmsService Sms.MyValueFirst
    Sms.GupShupConfig _ -> Domain.SmsService Sms.GupShup
  Domain.WhatsappServiceConfig whatsappCfg -> case whatsappCfg of
    Whatsapp.GupShupConfig _ -> Domain.WhatsappService Whatsapp.GupShup
  Domain.VerificationServiceConfig verificationCfg -> case verificationCfg of
    Verification.IdfyConfig _ -> Domain.VerificationService Verification.Idfy
    Verification.FaceVerificationConfig _ -> Domain.VerificationService Verification.InternalScripts
    Verification.GovtDataConfig -> Domain.VerificationService Verification.GovtData
  Domain.DriverBackgroundVerificationServiceConfig driverBackgroundVerificationCfg -> case driverBackgroundVerificationCfg of
    Verification.SafetyPortalConfig _ -> Domain.DriverBackgroundVerificationService Verification.SafetyPortal
  Domain.CallServiceConfig callCfg -> case callCfg of
    Call.ExotelConfig _ -> Domain.CallService Call.Exotel
  Domain.AadhaarVerificationServiceConfig aadhaarVerificationCfg -> case aadhaarVerificationCfg of
    AadhaarVerification.GridlineConfig _ -> Domain.AadhaarVerificationService AadhaarVerification.Gridline
  Domain.PaymentServiceConfig paymentCfg -> case paymentCfg of
    Payment.JuspayConfig _ -> Domain.PaymentService Payment.Juspay
    Payment.StripeConfig _ -> Domain.PaymentService Payment.Stripe
  Domain.RentalPaymentServiceConfig paymentCfg -> case paymentCfg of
    Payment.JuspayConfig _ -> Domain.RentalPaymentService Payment.Juspay
    Payment.StripeConfig _ -> Domain.RentalPaymentService Payment.Stripe
  Domain.IssueTicketServiceConfig ticketCfg -> case ticketCfg of
    Ticket.KaptureConfig _ -> Domain.IssueTicketService Ticket.Kapture
  Domain.NotificationServiceConfig notificationServiceCfg -> case notificationServiceCfg of
    Notification.FCMConfig _ -> Domain.NotificationService Notification.FCM
    Notification.PayTMConfig _ -> Domain.NotificationService Notification.PayTM
    Notification.GRPCConfig _ -> Domain.NotificationService Notification.GRPC
  Domain.TokenizationServiceConfig tokenizationConfig -> case tokenizationConfig of
    Tokenize.HyperVergeTokenizationServiceConfig _ -> Domain.TokenizationService Tokenize.HyperVerge
  Domain.BackgroundVerificationServiceConfig backgroundVerificationCfg -> case backgroundVerificationCfg of
    BackgroundVerification.CheckrConfig _ -> Domain.BackgroundVerificationService BackgroundVerification.Checkr

mkServiceConfig :: (MonadThrow m, Log m) => Data.Aeson.Value -> Domain.ServiceName -> m Domain.ServiceConfig
mkServiceConfig configJSON serviceName = either (\err -> throwError $ InternalError ("Unable to decode MerchantServiceConfigT.configJSON: " <> show configJSON <> " Error:" <> err)) return $ case serviceName of
  Domain.MapsService Maps.Google -> Domain.MapsServiceConfig . Maps.GoogleConfig <$> eitherValue configJSON
  Domain.MapsService Maps.OSRM -> Domain.MapsServiceConfig . Maps.OSRMConfig <$> eitherValue configJSON
  Domain.MapsService Maps.MMI -> Domain.MapsServiceConfig . Maps.MMIConfig <$> eitherValue configJSON
  Domain.MapsService Maps.NextBillion -> Domain.MapsServiceConfig . Maps.NextBillionConfig <$> eitherValue configJSON
  Domain.MapsService Maps.SelfTuned -> Left "No Config Found For SelfTuned."
  Domain.SmsService Sms.ExotelSms -> Domain.SmsServiceConfig . Sms.ExotelSmsConfig <$> eitherValue configJSON
  Domain.SmsService Sms.MyValueFirst -> Domain.SmsServiceConfig . Sms.MyValueFirstConfig <$> eitherValue configJSON
  Domain.SmsService Sms.GupShup -> Domain.SmsServiceConfig . Sms.GupShupConfig <$> eitherValue configJSON
  Domain.WhatsappService Whatsapp.GupShup -> Domain.WhatsappServiceConfig . Whatsapp.GupShupConfig <$> eitherValue configJSON
  Domain.VerificationService Verification.Idfy -> Domain.VerificationServiceConfig . Verification.IdfyConfig <$> eitherValue configJSON
  Domain.VerificationService Verification.InternalScripts -> Domain.VerificationServiceConfig . Verification.FaceVerificationConfig <$> eitherValue configJSON
  Domain.VerificationService Verification.GovtData -> Right $ Domain.VerificationServiceConfig Verification.GovtDataConfig
  Domain.DriverBackgroundVerificationService Verification.SafetyPortal -> Domain.DriverBackgroundVerificationServiceConfig . Verification.SafetyPortalConfig <$> eitherValue configJSON
  Domain.CallService Call.Exotel -> Domain.CallServiceConfig . Call.ExotelConfig <$> eitherValue configJSON
  Domain.CallService Call.Knowlarity -> Left "No Config Found For Knowlarity."
  Domain.AadhaarVerificationService AadhaarVerification.Gridline -> Domain.AadhaarVerificationServiceConfig . AadhaarVerification.GridlineConfig <$> eitherValue configJSON
  Domain.PaymentService Payment.Juspay -> Domain.PaymentServiceConfig . Payment.JuspayConfig <$> eitherValue configJSON
  Domain.PaymentService Payment.Stripe -> Domain.PaymentServiceConfig . Payment.StripeConfig <$> eitherValue configJSON
  Domain.RentalPaymentService Payment.Juspay -> Domain.RentalPaymentServiceConfig . Payment.JuspayConfig <$> eitherValue configJSON
  Domain.RentalPaymentService Payment.Stripe -> Domain.RentalPaymentServiceConfig . Payment.StripeConfig <$> eitherValue configJSON
  Domain.IssueTicketService Ticket.Kapture -> Domain.IssueTicketServiceConfig . Ticket.KaptureConfig <$> eitherValue configJSON
  Domain.NotificationService Notification.FCM -> Domain.NotificationServiceConfig . Notification.FCMConfig <$> eitherValue configJSON
  Domain.NotificationService Notification.PayTM -> Domain.NotificationServiceConfig . Notification.PayTMConfig <$> eitherValue configJSON
  Domain.NotificationService Notification.GRPC -> Domain.NotificationServiceConfig . Notification.GRPCConfig <$> eitherValue configJSON
  Domain.TokenizationService Tokenize.HyperVerge -> Domain.TokenizationServiceConfig . Tokenize.HyperVergeTokenizationServiceConfig <$> eitherValue configJSON
  Domain.BackgroundVerificationService BackgroundVerification.Checkr -> Domain.BackgroundVerificationServiceConfig . BackgroundVerification.CheckrConfig <$> eitherValue configJSON
  where
    eitherValue :: FromJSON a => A.Value -> Either Text a
    eitherValue value = case A.fromJSON value of
      A.Success a -> Right a
      A.Error err -> Left $ T.pack err
