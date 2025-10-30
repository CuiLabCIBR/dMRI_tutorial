#!/bin/bash
cd /home/david/Projects/MRtrix3_tutorial
BIDS_DIR="/home/david/Projects/MRtrix3_tutorial/BIDS"

for subject_path in ${BIDS_DIR}/*; do
    subject_name=$(basename ${subject_path})
    echo ${subject_name}
    #bash MRtrix3_pipeline.sh ${subject_name}
done