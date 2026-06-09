from pathlib import Path
import os
import glob
configfile: "config.json"
import pandas as pd

##### Config processing #####

# BARCODED / NON BARCODED
# TODO can be more libraries? 
library_tag = list(config["libraries"].keys())[0] # the original one

##### Sample table creation #####
def get_panda_sample_tab_from_config_one_lib(lib_name):
    lib_config = config["libraries"][lib_name]
    sample_tab = pd.DataFrame.from_dict(lib_config["samples"], orient="index")
    sample_tab["library"] = lib_name

    sample_tab['sample_ID'] = sample_tab.index.astype(str)
    sample_tab['sample_name_full'] = sample_tab['sample_name'] + '___' + sample_tab['sample_ID']
    return sample_tab

sample_tab = get_panda_sample_tab_from_config_one_lib(library_tag)

library_path_name = library_tag

RUN_DIR = config["run_dir"]

wildcard_constraints:
    sample_name = "|".join(sample_tab.sample_name)

sample_to_i7 = dict(zip(sample_tab.sample_name, sample_tab.i7_name))

#TODO easier create the 
# for sample_hash in sample_tab.sample_ID:
#     sample_name = config["libraries"][library_name]["samples"][sample_hash]["sample_name"]
#     hash_to_path[sample_hash]=os.path.join(library_name, "raw_reads", sample_name, sample_name + ".pod5") #TODO add {library_name} when copy to copy_raw_data

barcode_flag = sample_tab.i7_name[0]

if barcode_flag == "NON_BARCODED":
    is_barcoded = False
else:
    is_barcoded = True
    # takes the library name without the ID prefix
    RUN_DIR += "/" + library_path_name.split('_', 1)[1]

print(RUN_DIR)

def list_bam_files_per_sample(run_dir, sample_name):
    search_pattern_old = os.path.join(run_dir, sample_name, "*", "bam_pass", "*.bam")
    search_pattern_new = os.path.join(run_dir, sample_name, "*", "bam", "*.bam")
    matched_files = glob.glob(search_pattern_old) + glob.glob(search_pattern_new)
    print(matched_files)
    return matched_files 

rule all:
    input:
        expand("{library_path_name}/raw_reads/{sample_name}/{sample_name}.bam", library_path_name=library_path_name, sample_name=sample_tab.sample_name),

# merge bam files from one sample and all flowcells in the sample folder 
rule bam_merge:
    input: bams = lambda wildcards: list_bam_files_per_sample(RUN_DIR, wildcards.sample_name)
    output: bam_merged = "{library_path_name}/raw_reads/{sample_name}/{sample_name}.bam"
    params:
        input_count = lambda wildcards, input: len(input.bams),
        new_dir="{library_path_name}/raw_reads/{sample_name}"
    conda: "envs/samtools-merge-env.yaml"
    threads: workflow.cores * 0.75
    shell:
        """
        if [ {params.input_count} -eq 0 ]; then
            touch {output.bam_merged}
        elif [ {params.input_count} -eq 1 ]; then
            cp {input.bams[0]} {output.bam_merged}
        else
            samtools merge -@{threads} -b {input.bams} {output.bam_merged}
        fi
        """
