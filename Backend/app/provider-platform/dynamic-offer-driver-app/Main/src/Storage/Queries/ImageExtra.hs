{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Storage.Queries.ImageExtra where

import API.Types.UI.DriverOnboardingV2 as DTOV2
import qualified Data.List as DL
import qualified Data.Time as DT
import Domain.Types.DocumentVerificationConfig
import qualified Domain.Types.Image as DImage
import Domain.Types.Merchant hiding (Status (APPROVED))
import Domain.Types.Person (Person)
import Kernel.Beam.Functions
import qualified Kernel.Beam.Functions as B
import Kernel.External.Encryption
import Kernel.Prelude
import Kernel.Storage.Esqueleto as Esq hiding (on)
import Kernel.Types.Cac
import Kernel.Types.Common
import qualified Kernel.Types.Documents
import qualified Kernel.Types.Documents as Documents
import Kernel.Types.Error
import Kernel.Types.Id
import Kernel.Utils.Common (CacheFlow, EsqDBFlow, MonadFlow, fromMaybeM, getCurrentTime)
import Kernel.Utils.Error.Throwing
import qualified Sequelize as Se
import qualified Storage.Beam.Image as BeamI
import qualified Storage.Cac.TransporterConfig as QTC
import Storage.Queries.OrphanInstances.Image
import qualified Storage.Queries.Person as QP
import Tools.Error
import Utils.Common.Cac.KeyNameConstants

-- Extra code goes here --
findRecentByPersonIdAndImageType :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> DocumentType -> m [DImage.Image]
findRecentByPersonIdAndImageType personId imgType = do
  person <- B.runInReplica $ QP.findById personId >>= fromMaybeM (PersonNotFound personId.getId)
  transporterConfig <- QTC.findByMerchantOpCityId person.merchantOperatingCityId (Just (DriverId (cast personId))) >>= fromMaybeM (TransporterConfigNotFound person.merchantOperatingCityId.getId)
  let onboardingRetryTimeInHours = transporterConfig.onboardingRetryTimeInHours
      onBoardingRetryTimeInHours' = intToNominalDiffTime onboardingRetryTimeInHours
  now <- getCurrentTime
  findAllWithOptionsKV
    [ Se.And
        [Se.Is BeamI.personId $ Se.Eq $ getId personId, Se.Is BeamI.imageType $ Se.Eq imgType, Se.Is BeamI.createdAt $ Se.GreaterThanOrEq (hoursAgo onBoardingRetryTimeInHours' now)]
    ]
    (Se.Desc BeamI.createdAt)
    Nothing
    Nothing
  where
    hoursAgo i now = negate (3600 * i) `DT.addUTCTime` now

findRecentLatestByPersonIdAndImageType :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> DocumentType -> m (Maybe DImage.Image)
findRecentLatestByPersonIdAndImageType driverId imgType = do
  findAllWithKV
    [ Se.And
        [ Se.Is BeamI.personId $ Se.Eq driverId.getId,
          Se.Is BeamI.imageType $ Se.Eq imgType
        ]
    ]
    >>= \case
      [] -> pure Nothing
      images -> pure $ Just (DL.maximumBy (compare `on` (.createdAt)) images)

findByPersonIdImageTypeAndValidationStatus :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> DocumentType -> DImage.SelfieFetchStatus -> m (Maybe DImage.Image)
findByPersonIdImageTypeAndValidationStatus persondId docType fetchStatus = do
  case fetchStatus of
    DImage.APPROVED ->
      findOneWithKV
        [ Se.And
            [ Se.Is BeamI.personId $ Se.Eq $ getId persondId,
              Se.Is BeamI.imageType $ Se.Eq docType,
              Se.Is BeamI.verificationStatus $ Se.Eq (Just Documents.VALID)
            ]
        ]
    DImage.NEEDS_REVIEW ->
      findOneWithKV
        [ Se.And
            [ Se.Is BeamI.personId $ Se.Eq $ persondId.getId,
              Se.Is BeamI.imageType $ Se.Eq docType,
              Se.Is BeamI.verificationStatus $ Se.Eq (Just Documents.MANUAL_VERIFICATION_REQUIRED)
            ]
        ]

findImageByPersonIdAndImageTypeAndVerificationStatus :: (MonadFlow m, CacheFlow m r, EsqDBFlow m r) => Id Person -> DocumentType -> [Documents.VerificationStatus] -> m [DImage.Image]
findImageByPersonIdAndImageTypeAndVerificationStatus personId imgtype verificationStatus = do
  findAllWithKV
    [ Se.And
        [Se.Is BeamI.personId $ Se.Eq $ getId personId, Se.Is BeamI.imageType $ Se.Eq imgtype, Se.Is BeamI.verificationStatus $ Se.In (Just <$> verificationStatus)]
    ]

updateVerificationStatusOnlyById :: (EsqDBFlow m r, MonadFlow m, CacheFlow m r) => (Documents.VerificationStatus -> Kernel.Types.Id.Id DImage.Image -> m ())
updateVerificationStatusOnlyById verificationStatus (Kernel.Types.Id.Id id) = do
  _now <- getCurrentTime
  updateWithKV [Se.Set BeamI.verificationStatus (Just verificationStatus), Se.Set BeamI.updatedAt _now] [Se.Is BeamI.id $ Se.Eq id]

updateVerificationStatusByIdAndType ::
  (EsqDBFlow m r, MonadFlow m, CacheFlow m r) =>
  (Kernel.Types.Documents.VerificationStatus -> Kernel.Types.Id.Id DImage.Image -> DocumentType -> m ())
updateVerificationStatusByIdAndType verificationStatus (Kernel.Types.Id.Id id) imageType = do
  updateOneWithKV
    [Se.Set BeamI.verificationStatus (Just verificationStatus)]
    [ Se.And
        [ Se.Is BeamI.id $ Se.Eq id,
          Se.Is BeamI.imageType $ Se.Eq imageType
        ]
    ]

updateVerificationStatusAndFailureReason ::
  (EsqDBFlow m r, MonadFlow m, CacheFlow m r) =>
  (Kernel.Types.Documents.VerificationStatus -> DriverOnboardingError -> Kernel.Types.Id.Id DImage.Image -> m ())
updateVerificationStatusAndFailureReason verificationStatus failureReason (Kernel.Types.Id.Id id) = do
  _now <- getCurrentTime
  updateOneWithKV [Se.Set BeamI.verificationStatus (Just verificationStatus), Se.Set BeamI.failureReason (Just failureReason), Se.Set BeamI.updatedAt _now] [Se.Is BeamI.id $ Se.Eq id]
