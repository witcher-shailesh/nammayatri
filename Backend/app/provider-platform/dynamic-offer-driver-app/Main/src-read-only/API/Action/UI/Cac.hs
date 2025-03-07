{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module API.Action.UI.Cac where

import qualified Control.Lens
import qualified Data.Aeson
import qualified Domain.Action.UI.Cac as Domain.Action.UI.Cac
import qualified Domain.Types.Merchant
import qualified Domain.Types.MerchantOperatingCity
import qualified Domain.Types.Person
import qualified Environment
import EulerHS.Prelude
import qualified Kernel.Prelude
import qualified Kernel.Types.Id
import Kernel.Utils.Common
import Servant
import Storage.Beam.SystemConfigs ()
import Tools.Auth

type API = (TokenAuth :> "driver" :> "getUiConfigs" :> MandatoryQueryParam "toss" Kernel.Prelude.Int :> Get '[JSON] Data.Aeson.Object)

handler :: Environment.FlowServer API
handler = getDriverGetUiConfigs

getDriverGetUiConfigs ::
  ( ( Kernel.Types.Id.Id Domain.Types.Person.Person,
      Kernel.Types.Id.Id Domain.Types.Merchant.Merchant,
      Kernel.Types.Id.Id Domain.Types.MerchantOperatingCity.MerchantOperatingCity
    ) ->
    Kernel.Prelude.Int ->
    Environment.FlowHandler Data.Aeson.Object
  )
getDriverGetUiConfigs a2 a1 = withFlowHandlerAPI $ Domain.Action.UI.Cac.getDriverGetUiConfigs (Control.Lens.over Control.Lens._1 Kernel.Prelude.Just a2) a1
