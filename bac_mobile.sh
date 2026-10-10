#!/bin/bash

<< EOF
需要的docker镜像 bakta:1.12.0-6.0-light mob_suite:v3.1.9 integron_finder:v2.0.0 isescan:v1.7.3 phispy:v5.0.10 defense-finder:v3.0.0

#脚本信息如下:
编辑人:娄成旭
编辑说明: 细菌基因组注释脚本

#首次编辑
编辑时间: 2026.09.10
编辑说明: 


EOF

while getopts "i:o:t:" opt; do
    case $opt in
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        t) THREADS=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir>"
    #exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "警告: 输入文件夹件夹为空或不存在，请检查输入文件夹路径"
    #exit 1
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n注! 这是每次都会出现的第一个提示, 这是分析可移动元件专用的脚本"

echo -e "\n注! 这是每次都会出现的第二个提示, 请检查所有的文件是否为fasta格式, 并去掉所有文件名中的空格与中文"

echo -e "\n注! 这是每次都会出现的第三个提示, 脚本使用MobileElementFinder进行注释"

echo -e "\n注! 这是每次都会出现的第四个提示, MobileElementFinder 地址: https://pypi.org/project/MobileElementFinder"

# 0. 创建输出目录结构
mkdir -p "$OUTPUT_DIR/logdir"
mkdir -p "$OUTPUT_DIR/result"
mkdir -p "$OUTPUT_DIR/tempdir"

# 1. 文件后缀判断及文件数量统计
file_count=0
for file in "$INPUT_DIR"/*; do
    filename=$(basename "$file")

    if [[ ! "$filename" == *.fasta ]]; then
        echo "文件 $filename 后缀非fasta,请修改文件名后重试。"
        #exit 1
    fi

    if [[ "$filename" == *" "* ]]; then
        echo "文件 $filename 中包含空格,请修改文件名后重试。"
        #exit 1
    fi

    ((file_count++))

done

echo -e "\n输入文件夹中共有 $file_count 个文件"

# 2. 细菌基因组注释开始
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 细菌基因组注释开始"

for file in "$INPUT_DIR"/*; do
    filename=$(basename "$file" .fasta)

    mkdir -p "$OUTPUT_DIR/tempdir/$filename/bakta"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/card"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/vfdb"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/mob_suite"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/isescan"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/phispy"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/defense-finder"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/signalp"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/uniop"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/trf"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/macsyfinder"
    mkdir -p "$OUTPUT_DIR/tempdir/$filename/split"

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" staphb/bakta:1.12.0-6.0-light \
    bakta --db /db/db-light --keep-contig-headers --force --compliant \
           --prefix $filename --threads $THREADS --output $OUTPUT_DIR/tempdir/$filename/bakta $file \
          >> "$OUTPUT_DIR/logdir/1_bakta.log" 2>&1
 
    if [ -s "$OUTPUT_DIR/tempdir/$filename/bakta/$filename.txt" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename bakta分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename bakta分析失败"
        exit 1
    fi

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
    abricate --quiet --THREADS 24 --db card --minid 90 --mincov 90 $INPUT_DIR/${filename}.fasta > $OUTPUT_DIR/tempdir/$filename/card/${filename}_card.tab

    if [ -s "$OUTPUT_DIR/tempdir/$filename/card/${filename}_card.tab" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename card分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename card分析失败"
        exit 1
    fi

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
    abricate --quiet --THREADS 24 --db vfdb --minid 90 --mincov 90 $INPUT_DIR/${filename}.fasta > $OUTPUT_DIR/tempdir/$filename/vfdb/${filename}_vfdb.tab

    if [ -s "$OUTPUT_DIR/tempdir/$filename/vfdb/${filename}_vfdb.tab" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename vfdb分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename vfdb分析失败"
        exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" mob_suite:v3.1.9 \
    mob_recon --infile "$file" --prefix $filename --sample_id $filename --num_threads $THREADS \
              --run_overhang  --force --outdir "$OUTPUT_DIR/tempdir/$filename/mob_suite" \
              >> $OUTPUT_DIR/logdir/2_mob_suite.log  2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/mob_suite/$filename.contig_report.txt" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename mob_suite分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename mob_suite分析失败"
        ##exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" integron_finder:v2.0.0 \
    integron_finder --outdir "$OUTPUT_DIR/tempdir/$filename" \
                    --cpu 4 --func-annot --pdf --gbk "$file" \
                    >> $OUTPUT_DIR/logdir/3_integron.log 2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/Results_Integron_Finder_$filename/$filename.summary" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename integron_finder分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename integron_finder分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" isescan:v1.7.3 \
    isescan.py --seqfile "$file" --nthread $THREADS \
               --output "$OUTPUT_DIR/tempdir/$filename/isescan" \
               >> $OUTPUT_DIR/logdir/4_isescan.log 2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/isescan/in/$filename.fasta.csv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename isescan分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename isescan分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" phispy:v5.0.10 \
    phispy --output_choice 512 --threads $THREADS --file_prefix $filename \
           "$OUTPUT_DIR/tempdir/$filename/bakta/$filename.gbff" \
           -o "$OUTPUT_DIR/tempdir/$filename/phispy/" \
           >> $OUTPUT_DIR/logdir/5_phispy.log 2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/phispy/${filename}_prophage.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename phispy分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename phispy分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" defense-finder:v3.0.0 \
    defense-finder run $file  -c 0.9 -a \
                   --out-dir "$OUTPUT_DIR/tempdir/$filename/defense-finder/" \
                   >> $OUTPUT_DIR/logdir/6_defense-finder.log 2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/defense-finder/${filename}_defense_finder_genes.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename defense-finder分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename defense-finder分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" signalp_fast:v6.0.0 \
               --fastafile $file --organism other --format all --mode fast \
               --output_dir "$OUTPUT_DIR/tempdir/$filename/signalp/" \
               >> $OUTPUT_DIR/logdir/7_signalp.log 2>&1
    
    if [ -s "$OUTPUT_DIR/tempdir/$filename/signalp/prediction_results.txt" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename signalp分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename signalp分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" uniop:v1.0.0 \
    python /UniOP/src/UniOP -i "$file" -t $OUTPUT_DIR/tempdir/$filename/uniop >> $OUTPUT_DIR/logdir/8_uniop.log 2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/uniop/uniop.operon" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename uniop分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename uniop分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" trf:v4.09.1 \
    bash -c "cd $OUTPUT_DIR/tempdir/$filename/trf/ && /trf409.linux64 "$file" 2 5 7 80 10 50 2000 -l 10" >> $OUTPUT_DIR/logdir/9_trf.log 2>&1

    if [ -s "$OUTPUT_DIR/tempdir/$filename/trf/" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename trf分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename trf分析失败"
        #exit 1
    fi

    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" macsyfinder:v2.1.6 \
    macsyfinder --force --worker 24 --models TXSScan all --db-type unordered --models-dir /models \
                --sequence-db $OUTPUT_DIR/tempdir/$filename/bakta/$filename.faa \
                --out-dir $OUTPUT_DIR/tempdir/$filename/macsy \
                >> $OUTPUT_DIR/logdir/10_macsyfinder.log 2>&1

    awk -v out_dir="$OUTPUT_DIR/tempdir/$filename/split/" '/^LOCUS/ {close(out); out = $2 ".gbff"} \
    {print > (out_dir out)}' "$OUTPUT_DIR/tempdir/$filename/bakta/$filename.gbff"
 
    docker run --rm -v "$INPUT_DIR":"$INPUT_DIR" -v "$OUTPUT_DIR":"$OUTPUT_DIR" gipsy:v2.0.7 \
    bash -c "
        for gbff_file in $OUTPUT_DIR/tempdir/$filename/split/*.gbff; do
        /root/gipsy2 -q $\gbff_file -s /home/lcxu/software/gipsy/NC_004603_no_tRNA.gbff \
                     -o /home/lcxu/software/gipsy/out2 --force -res -vir -sym -met
                     >> $OUTPUT_DIR/logdir/7_gipsy.log 2>&1
        done
    "

done

echo -e "$(date '+%Y-%m-%d %H:%M:%S') 细菌基因组注释完成"