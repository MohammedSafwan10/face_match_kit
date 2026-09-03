/// Immutable identity of the bundled recognition and preprocessing pipeline.
abstract final class FacePipelineIdentity {
  static const schemaVersion = 2;
  static const modelId = 'opencv-sface-2021dec-int8-128';
  static const modelHash =
      '2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a';
  static const dimensions = 128;
  static const pipelineVersion =
      'canonical-rgb1600-yunet2023mar-sface-aligncrop-v1'
      '+opencv-2.2.1+4+litert-3.5.1+image-4.3.0'
      '+manifest-891edc554faff1ace955ebd23ff347fa719aed56188d89c112a06fdd9fd921db';
}
