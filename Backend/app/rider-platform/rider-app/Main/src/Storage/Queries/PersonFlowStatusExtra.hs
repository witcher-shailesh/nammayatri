module Storage.Queries.PersonFlowStatusExtra where

import Domain.Types.Person
import qualified Domain.Types.PersonFlowStatus as DPFS
import Kernel.Beam.Functions
import Kernel.Prelude
import Kernel.Types.Id
import Kernel.Utils.Common
import qualified Sequelize as Se
import qualified Storage.Beam.PersonFlowStatus as BeamPFS
import Storage.Queries.OrphanInstances.PersonFlowStatus ()

-- Extra code goes here --
create :: (MonadFlow m, EsqDBFlow m r) => DPFS.PersonFlowStatus -> m ()
create = createWithKV

getStatus :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> m (Maybe DPFS.FlowStatus)
getStatus (Id personId) = findOneWithKV [Se.Is BeamPFS.personId $ Se.Eq personId] <&> (DPFS.flowStatus <$>)

updateStatus :: (MonadFlow m, EsqDBFlow m r) => Id Person -> DPFS.FlowStatus -> m ()
updateStatus (Id personId) flowStatus = do
  now <- getCurrentTime
  updateOneWithKV
    [Se.Set BeamPFS.flowStatus flowStatus, Se.Set BeamPFS.updatedAt now]
    [Se.Is BeamPFS.personId $ Se.Eq personId]

deleteByPersonId :: (MonadFlow m, EsqDBFlow m r) => Id Person -> m ()
deleteByPersonId (Id personId) = deleteWithKV [Se.Is BeamPFS.personId $ Se.Eq personId]

updateToIdleMultiple :: (MonadFlow m, EsqDBFlow m r) => [Id Person] -> UTCTime -> m ()
updateToIdleMultiple personIds now =
  updateWithKV
    [Se.Set BeamPFS.flowStatus DPFS.IDLE, Se.Set BeamPFS.updatedAt now]
    [Se.Is BeamPFS.personId $ Se.In (getId <$> personIds)]
