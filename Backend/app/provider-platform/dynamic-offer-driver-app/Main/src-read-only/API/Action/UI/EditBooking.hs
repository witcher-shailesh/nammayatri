{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module API.Action.UI.EditBooking where

import qualified API.Types.UI.EditBooking
import qualified Control.Lens
import qualified Domain.Action.UI.EditBooking as Domain.Action.UI.EditBooking
import qualified Domain.Types.BookingUpdateRequest
import qualified Domain.Types.Merchant
import qualified Domain.Types.MerchantOperatingCity
import qualified Domain.Types.Person
import qualified Environment
import EulerHS.Prelude
import qualified Kernel.Prelude
import qualified Kernel.Types.APISuccess
import qualified Kernel.Types.Id
import Kernel.Utils.Common
import Servant
import Storage.Beam.SystemConfigs ()
import Tools.Auth

type API =
  ( TokenAuth :> "edit" :> "result" :> Capture "bookingUpdateRequestId" (Kernel.Types.Id.Id Domain.Types.BookingUpdateRequest.BookingUpdateRequest)
      :> ReqBody
           '[JSON]
           API.Types.UI.EditBooking.EditBookingRespondAPIReq
      :> Post '[JSON] Kernel.Types.APISuccess.APISuccess
  )

handler :: Environment.FlowServer API
handler = postEditResult

postEditResult ::
  ( ( Kernel.Types.Id.Id Domain.Types.Person.Person,
      Kernel.Types.Id.Id Domain.Types.Merchant.Merchant,
      Kernel.Types.Id.Id Domain.Types.MerchantOperatingCity.MerchantOperatingCity
    ) ->
    Kernel.Types.Id.Id Domain.Types.BookingUpdateRequest.BookingUpdateRequest ->
    API.Types.UI.EditBooking.EditBookingRespondAPIReq ->
    Environment.FlowHandler Kernel.Types.APISuccess.APISuccess
  )
postEditResult a3 a2 a1 = withFlowHandlerAPI $ Domain.Action.UI.EditBooking.postEditResult (Control.Lens.over Control.Lens._1 Kernel.Prelude.Just a3) a2 a1
