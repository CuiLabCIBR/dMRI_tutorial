#!/bin/bash

################################################################################
# Combined T1w and DWI Preprocessing Pipeline
# 
# This pipeline performs:
# 1. T1w anatomical preprocessing
# 2. DWI preprocessing
# 3. T1w-DWI registration
# 4. Atlas transformation to native and DWI space
# 5. Tractography and connectome construction
################################################################################

# ==============================================================================
# SETUP
# ==============================================================================

SUBJECT=$1 # "sub-001"
BIDS_DIR="./BIDS"
DERIVATIVES_DIR="./derivatives/${SUBJECT}"
TEMPLATE_DIR="./templates"
ATLAS_DIR="./atlases"

# Input directories (raw BIDS data)
ANAT_INPUT="${BIDS_DIR}/${SUBJECT}/anat"
DWI_INPUT="${BIDS_DIR}/${SUBJECT}/dwi"
FMAP_INPUT="${BIDS_DIR}/${SUBJECT}/fmap"

# Output directories (derivatives)
ANAT_OUTPUT="${DERIVATIVES_DIR}/anat"
DWI_OUTPUT="${DERIVATIVES_DIR}/dwi"

# Create output directories
mkdir -p ${ANAT_OUTPUT}
mkdir -p ${DWI_OUTPUT}

echo "=========================================="
echo "Combined Preprocessing Pipeline"
echo "=========================================="
echo "Subject: ${SUBJECT}"
echo "Raw data: ${BIDS_DIR}/${SUBJECT}"
echo "Derivatives: ${DERIVATIVES_DIR}"
echo ""

################################################################################
# PART 1: T1w ANATOMICAL PREPROCESSING
################################################################################

echo ""
echo "=========================================="
echo "PART 1: T1w ANATOMICAL PREPROCESSING"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 1.1: Intensity Non-Uniformity (INU) Correction
# ------------------------------------------------------------------------------

echo "Step 1.1: Running N4 bias field correction..."

T1W="${ANAT_INPUT}/${SUBJECT}_run-1_T1w.nii"

N4BiasFieldCorrection \
    -d 3 \
    -i ${T1W} \
    -o ${ANAT_OUTPUT}/${SUBJECT}_T1w_n4.nii.gz \
    -s 4 \
    -b [200] \
    -c [50x50x50x50,0.0000001]

T1W_N4="${ANAT_OUTPUT}/${SUBJECT}_T1w_n4.nii.gz"

echo "N4 correction completed: ${T1W_N4}"
echo ""

# ------------------------------------------------------------------------------
# Step 1.2: Brain Extraction (Skull Stripping)
# ------------------------------------------------------------------------------

echo "Step 1.2: Running brain extraction with OASIS template..."

antsBrainExtraction.sh \
    -d 3 \
    -a ${T1W_N4} \
    -e ${TEMPLATE_DIR}/T_template0.nii.gz \
    -m ${TEMPLATE_DIR}/T_template0_BrainCerebellumProbabilityMask.nii.gz \
    -f ${TEMPLATE_DIR}/T_template0_BrainCerebellumRegistrationMask.nii.gz \
    -o ${ANAT_OUTPUT}/${SUBJECT}_T1w_

echo "Brain extraction completed: ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionBrain.nii.gz"
echo ""

# ------------------------------------------------------------------------------
# Step 1.3: Spatial Normalization to MNI Space
# ------------------------------------------------------------------------------

echo "Step 1.3: Running spatial normalization to MNI space..."

MNI_BRAIN="${TEMPLATE_DIR}/tpl-MNI152NLin2009cAsym_res-01_desc-brain_T1w.nii.gz"

antsRegistrationSyNQuick.sh \
    -d 3 \
    -f ${MNI_BRAIN} \
    -m ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionBrain.nii.gz \
    -o ${ANAT_OUTPUT}/${SUBJECT}_T1w_to_MNI_ \
    -t s

echo "Normalization completed"
echo ""

# ------------------------------------------------------------------------------
# Step 1.4: Brain Tissue Segmentation (CSF, WM, GM)
# ------------------------------------------------------------------------------

echo "Step 1.4: Running tissue segmentation with FSL FAST..."

fast \
    -t 1 \
    -n 3 \
    -H 0.1 \
    -I 4 \
    -l 20.0 \
    -o ${ANAT_OUTPUT}/${SUBJECT}_T1w_brain_seg \
    ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionBrain.nii.gz

echo "Tissue segmentation completed"
echo ""

# ------------------------------------------------------------------------------
# Step 1.5: Create Binary Tissue Masks
# ------------------------------------------------------------------------------

echo "Step 1.5: Creating binary tissue masks..."

# CSF mask (label = 1)
fslmaths ${ANAT_OUTPUT}/${SUBJECT}_T1w_brain_seg_seg.nii.gz \
    -thr 1 -uthr 1 -bin \
    ${ANAT_OUTPUT}/${SUBJECT}_T1w_CSF_mask.nii.gz

# GM mask (label = 2)
fslmaths ${ANAT_OUTPUT}/${SUBJECT}_T1w_brain_seg_seg.nii.gz \
    -thr 2 -uthr 2 -bin \
    ${ANAT_OUTPUT}/${SUBJECT}_T1w_GM_mask.nii.gz

# WM mask (label = 3)
fslmaths ${ANAT_OUTPUT}/${SUBJECT}_T1w_brain_seg_seg.nii.gz \
    -thr 3 -uthr 3 -bin \
    ${ANAT_OUTPUT}/${SUBJECT}_T1w_WM_mask.nii.gz

echo "Binary masks created"
echo ""

# ------------------------------------------------------------------------------
# Step 1.6: Transform Atlas from MNI to Native T1w Space
# ------------------------------------------------------------------------------

echo "Step 1.6: Transforming Schaefer 400 atlas from MNI to native T1w space..."

ATLAS_FILE="${ATLAS_DIR}/Schaefer2018_400Parcels_7Networks_order_FSLMNI152_1mm.nii.gz"
INVERSE_WARP="${ANAT_OUTPUT}/${SUBJECT}_T1w_to_MNI_1InverseWarp.nii.gz"
AFFINE_MAT="${ANAT_OUTPUT}/${SUBJECT}_T1w_to_MNI_0GenericAffine.mat"

antsApplyTransforms \
    -d 3 \
    -i ${ATLAS_FILE} \
    -r ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionBrain.nii.gz \
    -o ${ANAT_OUTPUT}/schaefer400.nii.gz \
    -n NearestNeighbor \
    -t ${INVERSE_WARP} \
    -t [${AFFINE_MAT},1]

echo "Atlas transformed to native T1w space: ${ANAT_OUTPUT}/schaefer400.nii.gz"
echo ""

echo "T1w preprocessing completed!"
echo ""

################################################################################
# PART 2: DWI PREPROCESSING
################################################################################

echo ""
echo "=========================================="
echo "PART 2: DWI PREPROCESSING"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 2.1: Convert NIFTI to MIF Format
# ------------------------------------------------------------------------------

echo "Step 2.1: Converting NIFTI to MIF format..."

mrconvert ${DWI_INPUT}/${SUBJECT}_dir-PA_dwi.nii ${DWI_OUTPUT}/dwi.mif \
    -fslgrad ${DWI_INPUT}/${SUBJECT}_dir-PA_dwi.bvec ${DWI_INPUT}/${SUBJECT}_dir-PA_dwi.bval \
    -force

echo "Conversion completed"
echo ""

# ------------------------------------------------------------------------------
# Step 2.2: Denoising
# ------------------------------------------------------------------------------

echo "Step 2.2: Running MP-PCA denoising..."

dwidenoise ${DWI_OUTPUT}/dwi.mif ${DWI_OUTPUT}/dwi_den.mif -force

echo "Denoising completed"
echo ""

# ------------------------------------------------------------------------------
# Step 2.3: Unringing (Gibbs Artifact Removal)
# ------------------------------------------------------------------------------

echo "Step 2.3: Running Gibbs unringing..."

mrdegibbs ${DWI_OUTPUT}/dwi_den.mif ${DWI_OUTPUT}/dwi_den_unr.mif -axes 0,1 -force

echo "Unringing completed"
echo ""

# ------------------------------------------------------------------------------
# Step 2.4: Motion and Distortion Correction
# ------------------------------------------------------------------------------

echo "Step 2.4: Running motion and distortion correction..."

# Extract b0 volumes from PA data
dwiextract ${DWI_OUTPUT}/dwi_den_unr.mif ${DWI_OUTPUT}/b0_PA.mif -bzero -force
mrmath ${DWI_OUTPUT}/b0_PA.mif mean ${DWI_OUTPUT}/b0_PA_mean.mif -axis 3 -force

# Process AP b0 for topup
mrconvert ${FMAP_INPUT}/${SUBJECT}_acq-dwi_dir-AP_epi.nii ${DWI_OUTPUT}/b0_AP.mif -force
mrmath ${DWI_OUTPUT}/b0_AP.mif mean ${DWI_OUTPUT}/b0_AP_mean.mif -axis 3 -force

# Combine PA and AP b0s for topup
mrcat ${DWI_OUTPUT}/b0_PA_mean.mif ${DWI_OUTPUT}/b0_AP_mean.mif ${DWI_OUTPUT}/b0_pair.mif -axis 3 -force

# Run preprocessing with topup and eddy
dwifslpreproc ${DWI_OUTPUT}/dwi_den_unr.mif ${DWI_OUTPUT}/dwi_den_unr_preproc.mif \
    -pe_dir PA \
    -rpe_pair \
    -se_epi ${DWI_OUTPUT}/b0_pair.mif \
    -align_seepi \
    -readout_time 0.0836197 \
    -eddy_options " --slm=linear --data_is_shelled" \
    -force

echo "Motion and distortion correction completed"
echo ""

# ------------------------------------------------------------------------------
# Step 2.5: Bias Field Correction
# ------------------------------------------------------------------------------

echo "Step 2.5: Running bias field correction..."

dwibiascorrect ants ${DWI_OUTPUT}/dwi_den_unr_preproc.mif ${DWI_OUTPUT}/dwi_den_unr_preproc_unbiased.mif \
    -bias ${DWI_OUTPUT}/bias.mif \
    -force

echo "Bias field correction completed"
echo ""

# ------------------------------------------------------------------------------
# Step 2.6: Brain Mask Estimation
# ------------------------------------------------------------------------------

echo "Step 2.6: Estimating brain mask..."

dwi2mask ${DWI_OUTPUT}/dwi_den_unr_preproc_unbiased.mif ${DWI_OUTPUT}/dwi_mask.mif -force

echo "Brain mask created"
echo ""

echo "DWI preprocessing completed!"
echo ""

################################################################################
# PART 3: T1w-DWI REGISTRATION
################################################################################

echo ""
echo "=========================================="
echo "PART 3: T1w-DWI REGISTRATION"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 3.1: Convert b0 to NIFTI and Register T1w to DWI Space
# ------------------------------------------------------------------------------

echo "Step 3.1: Registering T1w to DWI b0 space..."

# Compute mean b0 after preprocessing
dwiextract ${DWI_OUTPUT}/dwi_den_unr_preproc_unbiased.mif ${DWI_OUTPUT}/b0_PA_preproc.mif -bzero -force
mrmath ${DWI_OUTPUT}/b0_PA_preproc.mif mean ${DWI_OUTPUT}/b0_PA_preproc_mean.mif -axis 3 -force
mrconvert ${DWI_OUTPUT}/b0_PA_preproc_mean.mif ${DWI_OUTPUT}/b0_PA_preproc_mean.nii.gz -force

# Register T1w_Brain to b0
flirt -in ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionBrain.nii.gz \
      -ref ${DWI_OUTPUT}/b0_PA_preproc_mean.nii.gz \
      -out ${DWI_OUTPUT}/T1w_Brain_b0.nii.gz \
      -omat ${DWI_OUTPUT}/T1w_to_b0.mat \
      -dof 6

# Compute inverse transformation
convert_xfm -omat ${DWI_OUTPUT}/b0_to_T1w.mat -inverse ${DWI_OUTPUT}/T1w_to_b0.mat

echo "T1w-DWI registration completed"
echo ""

# Register T1w with skull to b0
flirt -in ${ANAT_OUTPUT}/${SUBJECT}_T1w_n4.nii.gz \
      -ref ${DWI_OUTPUT}/b0_PA_preproc_mean.nii.gz \
      -out ${DWI_OUTPUT}/T1w_b0.nii.gz \
      -init ${DWI_OUTPUT}/T1w_to_b0.mat \
      -applyxfm

# ------------------------------------------------------------------------------
# Step 3.2: Transform T1w Brain Mask to DWI Space
# ------------------------------------------------------------------------------

echo "Step 3.2: Transforming T1w brain mask to DWI space..."

flirt -in ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionMask.nii.gz \
      -ref ${DWI_OUTPUT}/b0_PA_preproc_mean.nii.gz \
      -out ${DWI_OUTPUT}/T1w_mask_b0.nii.gz \
      -init ${DWI_OUTPUT}/T1w_to_b0.mat \
      -applyxfm \
      -interp nearestneighbour

mrconvert ${DWI_OUTPUT}/T1w_mask_b0.nii.gz ${DWI_OUTPUT}/T1w_mask_b0.mif -force

echo "T1w mask transformed to DWI space"
echo ""

# Mask preprocessed DWI data using T1w_mask
mrcalc ${DWI_OUTPUT}/dwi_den_unr_preproc_unbiased.mif ${DWI_OUTPUT}/T1w_mask_b0.mif -mult ${DWI_OUTPUT}/dwi_preproc_masked.mif -force


# ------------------------------------------------------------------------------
# Step 3.3: Transform Schaefer Atlas to DWI B0 Space
# ------------------------------------------------------------------------------

echo "Step 3.3: Transforming Schaefer 400 atlas to DWI b0 space..."

flirt -in ${ANAT_OUTPUT}/schaefer400.nii.gz \
      -ref ${DWI_OUTPUT}/b0_PA_preproc_mean.nii.gz \
      -out ${DWI_OUTPUT}/schaefer400_b0.nii.gz \
      -init ${DWI_OUTPUT}/T1w_to_b0.mat \
      -applyxfm \
      -interp nearestneighbour

# Convert to MIF format for MRtrix
mrconvert ${DWI_OUTPUT}/schaefer400_b0.nii.gz ${DWI_OUTPUT}/schaefer400_b0.mif -force

echo "Atlas transformed to DWI space: ${DWI_OUTPUT}/schaefer400_b0.mif"
echo ""

################################################################################
# PART 4: DTI MODEL FITTING
################################################################################

echo ""
echo "=========================================="
echo "PART 4: DTI MODEL FITTING"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 4.1: Tensor Estimation
# ------------------------------------------------------------------------------

echo "Step 4.1: Estimating diffusion tensor..."

dwi2tensor ${DWI_OUTPUT}/dwi_preproc_masked.mif ${DWI_OUTPUT}/tensor.mif \
    -mask ${DWI_OUTPUT}/T1w_mask_b0.mif \
    -force

echo "Tensor estimation completed"
echo ""

# ------------------------------------------------------------------------------
# Step 4.2: Compute Tensor Metrics
# ------------------------------------------------------------------------------

echo "Step 4.2: Computing tensor metrics (FA, MD, AD, RD)..."

tensor2metric ${DWI_OUTPUT}/tensor.mif \
    -fa ${DWI_OUTPUT}/FA.mif \
    -adc ${DWI_OUTPUT}/MD.mif \
    -ad ${DWI_OUTPUT}/AD.mif \
    -rd ${DWI_OUTPUT}/RD.mif \
    -vector ${DWI_OUTPUT}/vector.mif \
    -mask ${DWI_OUTPUT}/T1w_mask_b0.mif \
    -force

echo "Tensor metrics computed"
echo ""

################################################################################
# PART 5: FIBER ORIENTATION DISTRIBUTION
################################################################################

echo ""
echo "=========================================="
echo "PART 5: FIBER ORIENTATION DISTRIBUTION"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 5.1: Response Function Estimation
# ------------------------------------------------------------------------------

echo "Step 5.1: Estimating response functions..."

dwi2response dhollander ${DWI_OUTPUT}/dwi_preproc_masked.mif \
    ${DWI_OUTPUT}/wm_response.txt \
    ${DWI_OUTPUT}/gm_response.txt \
    ${DWI_OUTPUT}/csf_response.txt \
    -voxels ${DWI_OUTPUT}/RF_voxels.mif \
    -force

echo "Response functions estimated"
echo ""

# ------------------------------------------------------------------------------
# Step 5.2: Multi-Shell Multi-Tissue CSD
# ------------------------------------------------------------------------------

echo "Step 5.2: Running multi-shell multi-tissue CSD..."

dwi2fod msmt_csd ${DWI_OUTPUT}/dwi_preproc_masked.mif \
    -mask ${DWI_OUTPUT}/T1w_mask_b0.mif \
    ${DWI_OUTPUT}/wm_response.txt ${DWI_OUTPUT}/wmfod.mif \
    ${DWI_OUTPUT}/gm_response.txt ${DWI_OUTPUT}/gm.mif \
    ${DWI_OUTPUT}/csf_response.txt ${DWI_OUTPUT}/csf.mif \
    -force

echo "FOD estimation completed"
echo ""

# ------------------------------------------------------------------------------
# Step 5.3: Intensity Normalization
# ------------------------------------------------------------------------------

echo "Step 5.3: Running intensity normalization..."

mtnormalise ${DWI_OUTPUT}/wmfod.mif ${DWI_OUTPUT}/wmfod_norm.mif \
    ${DWI_OUTPUT}/gm.mif ${DWI_OUTPUT}/gm_norm.mif \
    ${DWI_OUTPUT}/csf.mif ${DWI_OUTPUT}/csf_norm.mif \
    -mask ${DWI_OUTPUT}/T1w_mask_b0.mif \
    -force

echo "Intensity normalization completed"
echo ""

################################################################################
# PART 6: ANATOMICALLY-CONSTRAINED TRACTOGRAPHY
################################################################################

echo ""
echo "=========================================="
echo "PART 6: TRACTOGRAPHY"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 6.1: Generate 5-Tissue-Type (5TT) Image
# ------------------------------------------------------------------------------

echo "Step 6.1: Generating 5TT segmentation..."

5ttgen fsl ${DWI_OUTPUT}/T1w_b0.nii.gz ${DWI_OUTPUT}/T1w_5tt.mif \
    -sgm_amyg_hipp \
    -nocrop \
    -force

echo "5TT image created"
echo ""

# ------------------------------------------------------------------------------
# Step 6.2: Generate Grey Matter-White Matter Interface
# ------------------------------------------------------------------------------

echo "Step 6.2: Generating GM-WM interface for seeding..."

5tt2gmwmi ${DWI_OUTPUT}/T1w_5tt.mif ${DWI_OUTPUT}/gmwmSeed.mif -force

echo "GM-WM interface created"
echo ""

# ------------------------------------------------------------------------------
# Step 6.3: Generate Whole-Brain Tractogram
# ------------------------------------------------------------------------------

echo "Step 6.3: Generating whole-brain tractogram (10M streamlines)..."

tckgen -act ${DWI_OUTPUT}/T1w_5tt.mif \
    -backtrack \
    -seed_gmwmi ${DWI_OUTPUT}/gmwmSeed.mif \
    -minlength 30 \
    -maxlength 250 \
    -cutoff 0.06 \
    -select 10M \
    ${DWI_OUTPUT}/wmfod_norm.mif ${DWI_OUTPUT}/tracks_10M.tck \
    -force

echo "Tractogram generation completed"
echo ""

# ------------------------------------------------------------------------------
# Step 6.4: SIFT2 Filtering
# ------------------------------------------------------------------------------

echo "Step 6.4: Running SIFT2 to compute streamline weights..."

tcksift2 -act ${DWI_OUTPUT}/T1w_5tt.mif \
    ${DWI_OUTPUT}/tracks_10M.tck \
    ${DWI_OUTPUT}/wmfod_norm.mif \
    ${DWI_OUTPUT}/sift_10M.txt \
    -force

echo "SIFT2 completed"
echo ""

################################################################################
# PART 7: CONNECTOME CONSTRUCTION
################################################################################

echo ""
echo "=========================================="
echo "PART 7: CONNECTOME CONSTRUCTION"
echo "=========================================="
echo ""

# ------------------------------------------------------------------------------
# Step 7.1: Generate Structural Connectivity Matrix
# ------------------------------------------------------------------------------

echo "Step 7.1: Generating structural connectivity matrix..."

tck2connectome -symmetric \
    -zero_diagonal \
    -scale_invnodevol \
    -assignment_radial_search 2 \
    -tck_weights_in ${DWI_OUTPUT}/sift_10M.txt \
    ${DWI_OUTPUT}/tracks_10M.tck \
    ${DWI_OUTPUT}/schaefer400_b0.mif \
    ${DWI_OUTPUT}/sc_schaefer400_10M.csv \
    -force

echo "Structural connectivity matrix created: ${DWI_OUTPUT}/sc_schaefer400_10M.csv"
echo ""

################################################################################
# SUMMARY
################################################################################

echo ""
echo "=========================================="
echo "PIPELINE COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo ""
echo "Key outputs:"
echo ""
echo "T1w Anatomical:"
echo "  - N4 corrected:            ${ANAT_OUTPUT}/${SUBJECT}_T1w_n4.nii.gz"
echo "  - Brain extracted:         ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionBrain.nii.gz"
echo "  - Brain mask:              ${ANAT_OUTPUT}/${SUBJECT}_T1w_BrainExtractionMask.nii.gz"
echo "  - Tissue segmentation:     ${ANAT_OUTPUT}/${SUBJECT}_T1w_brain_seg_seg.nii.gz"
echo "  - Atlas (T1w space):       ${ANAT_OUTPUT}/schaefer400.nii.gz"
echo ""
echo "DWI Preprocessing:"
echo "  - Preprocessed DWI:        ${DWI_OUTPUT}/dwi_den_unr_preproc_unbiased.mif"
echo "  - Brain mask:              ${DWI_OUTPUT}/dwi_mask.mif"
echo "  - Atlas (DWI space):       ${DWI_OUTPUT}/schaefer400_b0.mif"
echo ""
echo "DTI Metrics:"
echo "  - FA map:                  ${DWI_OUTPUT}/FA.mif"
echo "  - MD map:                  ${DWI_OUTPUT}/MD.mif"
echo "  - AD map:                  ${DWI_OUTPUT}/AD.mif"
echo "  - RD map:                  ${DWI_OUTPUT}/RD.mif"
echo ""
echo "FOD and Tractography:"
echo "  - Normalized WM FOD:       ${DWI_OUTPUT}/wmfod_norm.mif"
echo "  - 5TT image:               ${DWI_OUTPUT}/T1w_5tt.mif"
echo "  - Tractogram:              ${DWI_OUTPUT}/tracks_10M.tck"
echo "  - SIFT2 weights:           ${DWI_OUTPUT}/sift_10M.txt"
echo ""
echo "Connectome:"
echo "  - Connectivity matrix:     ${DWI_OUTPUT}/sc_schaefer400_10M.csv"
echo ""
echo "Done!"
echo ""
