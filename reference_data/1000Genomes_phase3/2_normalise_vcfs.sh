#!/usr/bin/env bash
#

cores=8

# Download reference genome
mkdir -p output/ref_grch37
cd output/ref_grch37
ref_name=Homo_sapiens.GRCh37.dna.toplevel.fa.bgz
if [ ! -f $ref_name ]; then
  wget ftp://ftp.ensembl.org/pub/grch37/update/fasta/homo_sapiens/dna/Homo_sapiens.GRCh37.dna.toplevel.fa.gz
  zcat < Homo_sapiens.GRCh37.dna.toplevel.fa.gz | bgzip -c > $ref_name
  samtools faidx $ref_name
fi
cd ../..

# Change to vcf_norm folder
mkdir -p output/vcf_norm
cd output/vcf_norm

# Run normalisation
in_ref=../ref_grch37/$ref_name
for vcf in ../vcf/*.vcf.gz; do
  out_vcf=$(basename $vcf)
  echo "zcat < $vcf | \
  bcftools filter -e'MAF<0.01' -Ov | \
  bcftools norm -Ov -m -any | \
  bcftools norm -Ov -f $in_ref | \
  bcftools annotate -Ov -x ID -I +%CHROM:%POS:%REF:%ALT | \
  bgzip -c > $out_vcf"
done | parallel -j $(($cores/2)) # Each requires 2 cores
cd ../..
