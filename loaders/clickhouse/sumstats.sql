create database if not exists sumstats;

drop table sumstats.gwas_test
-- ## test first 2300 files, ~ 100 studies
create table if not exists sumstats.gwas_test(
    chip String,
    study_id String,
    trait_code String,
    variant_id_b37 String,
    chrom String,
    pos_b37 UInt32,
    segment UInt32 MATERIALIZED (intDiv(pos_b37,1000000)),
    ref_al String,
    alt_al String,
    beta Float64,
    se Float64,
    pval Float64,
    n_samples_variant_level Nullable(UInt32),
    n_samples_study_level Nullable(UInt32),
    n_cases_variant_level Nullable(UInt32),
    n_cases_study_level Nullable(UInt32),
    eaf Nullable(Float64),
    maf Nullable(Float64),
    info Nullable(Float64),
    is_cc String)
engine=Log;
-- gsutil ls -r gs://genetics-portal-sumstats/gwas/** | head -n  2300 |  xargs -P 16 -I {} sh -c 'CHIP=`echo {} | cut -d/ -f 5`; STUDY=`echo {} | cut -d/ -f 6`; TRAIT=`echo {} | cut -d/ -f 7`; gsutil cat {} | zcat | sed 1d | sed -e "s/^/$CHIP\t$STUDY\t$TRAIT\t/; :0 s/\t\t/\t\\\\N\t/;t0"  | clickhouse-client -h 127.0.0.1 --query="insert into sumstats.gwas_test format TabSeparated"; echo {} >> done.log;'



create table if not exists sumstats.gwas_log(
    chip String,
    study_id String,
    trait_code String,
    variant_id_b37 String,
    chrom String,
    pos_b37 UInt32,
    ref_al String,
    alt_al String,
    beta Float64,
    se Float64,
    pval Float64,
    n_samples_variant_level Nullable(UInt32),
    n_samples_study_level Nullable(UInt32),
    n_cases_variant_level Nullable(UInt32),
    n_cases_study_level Nullable(UInt32),
    eaf Nullable(Float64),
    maf Nullable(Float64),
    info Nullable(Float64),
    is_cc String)
engine=Log;

-- Load all gwas summary stats file by making a recursive, flattened list:
-- gsutil ls -r gs://genetics-portal-sumstats/gwas/** | xargs -P 16 -I {} sh -c 'CHIP=`echo {} | cut -d/ -f 5`; STUDY=`echo {} | cut -d/ -f 6`; TRAIT=`echo {} | cut -d/ -f 7`; gsutil cat {} | zcat | sed 1d | sed -e "s/^/$CHIP\t$STUDY\t$TRAIT\t/" | clickhouse-client -h 127.0.0.1 --query="insert into sumstats.gwas_log format TabSeparated"; echo {} >> done.log;'

-- The above imports all empty fields (integers or floats) as zeros rather than
-- NULL. It's probably ok for this set, since there should be no zero in the
-- input, however another way is to replace the empties with \N with sed:
-- gsutil ls -r gs://genetics-portal-sumstats/gwas/** | xargs -P 16 -I {} sh -c 'CHIP=`echo {} | cut -d/ -f 5`; STUDY=`echo {} | cut -d/ -f 6`; TRAIT=`echo {} | cut -d/ -f 7`; gsutil cat {} | zcat | sed 1d | sed -e "s/^/$CHIP\t$STUDY\t$TRAIT\t/; :0 s/\t\t/\t\\N\t/;t0"  | clickhouse-client -h 127.0.0.1 --query="insert into sumstats.gwas_log format TabSeparated"; echo {} >> done.log;'
-- do however consider that sed look aheads slow the command considerably
-- more info at https://github.com/yandex/ClickHouse/issues/469
-- sed trickery from: https://stackoverflow.com/questions/30109554/how-do-i-replace-empty-strings-in-a-tsv-with-a-value




-- Once done, check loading is complete by making a file list:
-- clickhouse-client -h 127.0.0.1 --query="select chip,study_id,trait_code, count(*) from sumstats.gwas_log group by chip, study_id, trait_code format TSV" > done.tsv

-- cat done.tsv | awk -v OFS=',' '{print $4,$2,$3}' | sort | tee done.sorted.tsv | tail


-- see if there are any zeros:
-- awk '{if ($5 = 0) print $0}' < done.tsv

-- compare with the input list:
-- gsutil ls -r gs://genetics-portal-sumstats/gwas/genome_wide/** > filelist.tsv
-- cat filelist.tsv| cut -d/ -f 8- | sed 's/-/\t/g; s/.tsv.gz//' | sed 's/\t/,/g' | sort | tee filelist.sorted.tsv | tail
-- comm -23 <(cat filelist.sorted.tsv) <(cat done.sorted.tsv)

-- when you are happy you have everything, create a mergeTree table:

create table if not exists sumstats.gwas
engine MergeTree partition by (chrom, segment) order by (pos_b37)
as select
    cast(assumeNotNull(chip) as Enum8('genome_wide' = 1, 'immunochip' = 2, 'metabochip' = 3 )) as chip,
    assumeNotNull(study_id) as study_id,
    assumeNotNull(trait_code) as trait_code,
    assumeNotNull(variant_id_b37) as variant_id_b37,
    assumeNotNull(chrom) as chrom,
    assumeNotNull(segment) as segment,
    assumeNotNull(pos_b37) as pos_b37,
    assumeNotNull(ref_al) as ref_al,
    assumeNotNull(alt_al) as alt_al,
    assumeNotNull(beta) as beta,
    assumeNotNull(se) as se,
    assumeNotNull(pval) as pval,
    if(n_samples_variant_level = 0, NULL ,n_samples_variant_level) as n_samples_variant_level,
    if(n_samples_study_level = 0, NULL ,n_samples_study_level) as n_samples_study_level,
    if(n_cases_study_level = 0, NULL ,n_cases_study_level) as n_cases_study_level,
    if(n_cases_variant_level = 0, NULL ,n_cases_variant_level) as n_cases_variant_level,
    if(eaf = 0, NULL ,eaf) as eaf,
    if(maf = 0, NULL ,maf) as maf,
    if(info = 0, NULL ,info) as info,

    if(is_cc = 'True', toUInt8(1), toUInt8(0)) as is_cc

from sumstats.gwas_test;


create table if not exists sumstats.molecular_qtl_log(
    experiment String,
    study_id String,
    tissue String,
    biomarker String,
    variant_id_b37 String,
    chrom String,
    pos_b37 UInt32,
    ref_al String,
    alt_al String,
    beta Float64,
    se Float64,
    pval Float64,
    n_samples_variant_level Nullable(UInt32),
    n_samples_study_level Nullable(UInt32),
    n_cases_variant_level Nullable(UInt32),
    n_cases_study_level Nullable(UInt32),
    eaf Nullable(Float64),
    maf Nullable(Float64),
    info Nullable(Float64),
    is_cc String)
engine=Log;





create table if not exists sumstats.molecular_qtl
engine MergeTree partition by (chrom) order by (pos_b37)
as select
    CAST(assumeNotNull(experiment) AS Enum8('eqtl' = 1, 'pqtl' = 2, 'cell_counts' = 3, 'metabolites' = 4)) AS experiment,
    assumeNotNull(study_id) as study_id,
    assumeNotNull(tissue) as tissue,
    assumeNotNull(biomarker) as biomarker,
    assumeNotNull(variant_id_b37) as variant_id_b37,
    assumeNotNull(chrom) as chrom,
    assumeNotNull(pos_b37) as pos_b37,
    assumeNotNull(ref_al) as ref_al,
    assumeNotNull(alt_al) as alt_al,
    assumeNotNull(beta) as beta,
    assumeNotNull(se) as se,
    assumeNotNull(pval) as pval,
    n_samples_variant_level,
    -- if(n_samples_variant_level = 0, NULL ,n_samples_variant_level) as n_samples_variant_level,
    n_samples_study_level,
    n_cases_variant_level,
    n_cases_study_level,
    eaf,
    maf,
    info,

    cast(is_cc AS UInt8('True' = 1, 'False' = 0)) as is_cc

from sumstats.molecular_qtl_log;



