#!/bin/bash

<< EOF
需要的docker镜像 fastqcp:v1.0.0、choppstat:v1.0.0、unicycler:v0.5.1

#脚本信息如下:
编辑人:娄成旭
脚本说明: 这个脚本用于细菌2代、3代单独及混合拼接

#首次编辑
编辑时间: 2026.09.04
编辑说明:
1) 脚本重构，优化了代码结构和逻辑
2) 使用nanostat和chopper代替fastplong进行三代数据质控

#二次编辑
编辑时间: 2026.09.07
编辑说明:
1) 修复了三代数据质控中NanoStat和chopper的输入文件
2) 完善了步骤的判断逻辑及提示信息

#三次编辑
编辑时间: 2026.09.23
编辑说明:
1) 修复了在2+3模式下, 由于三代数据的判定引起的bug
2) 加入了-f参数, 用于判断三代数据是否是合并后的数据, Y代表是, N代表否
3) 指定kmers参数为77,99,111,121, 提升分析速度

EOF

while getopts "1:2:3:i:o:t:n:m:f:" opt; do
    case $opt in
        1) SINGLE=$OPTARG ;;
        2) PAIR=$OPTARG ;;
        3) TGS=$OPTARG ;;
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        t) THREADS=$OPTARG ;; 
        n) sample=$OPTARG ;;
        m) MODE=$OPTARG ;;
        f) FORMAT=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$OUTPUT_DIR" ] || [ -z "$MODE" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir> -t <threads> -m 2"
    echo "Usage: $0 -i <input_dir> -o <output_dir> -t <threads> -m 3"
    echo "Usage: $0 -1 <single_file> -2 <pair_file> -3 <tgs_file> -o <output_dir> -t <threads> -m 23"
    echo "注! -m后面为模式选择, 2代表二代数据, 3代表三代数据, 23代表二代+三代数据, -i后面是二三代批量处理"
    exit 1
fi

# 检查输出文件夹是否为空
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "输出文件夹不存在"
    exit 1
fi

# 设置THREADS的默认值为24
if [ -z "$THREADS" ]; then
    THREADS=24
fi

# 去掉输出文件夹路径末尾的斜杠确保后续流程无误
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n"
echo -e "注! 这是每次都会出现的第一个提示, -1后为二代数据R1端, -2后面为二代数据R2端, -3后面为三代数据文件夹(确保只有测序文件), -n后面为自定义样本名称"
echo -e "注! 这是每次都会出现的第二个提示, 脚本使用fastp(v1.0.1)进行二代数据质控, 地址: https://github.com/OpenGene/fastp"
echo -e "注! 这是每次都会出现的第三个提示, 脚本使用nanostat(v1.4.0)进行二代数据质控, 地址: https://github.com/wdecoster/nanostat"
echo -e "注! 这是每次都会出现的第四个提示, 脚本使用chopper(v0.13.0)进行三代数据质控, 地址: https://github.com/wdecoster/chopper"
echo -e "注! 这是每次都会出现的第五个提示, 脚本使用unicycler(v0.5.1)进行组装，地址: https://github.com/rrwick/Unicycler"

# 0. 创建输出目录结构
mkdir -p $OUTPUT_DIR/logdir
mkdir -p $OUTPUT_DIR/result
mkdir -p $OUTPUT_DIR/tempdir

if [ "$MODE" = "2" ]; then

    find "$INPUT_DIR" -type f \( -name "*R1*.fastq*" -o -name "*R1*.fq*" -o -name "*1_001.fastq*" -o -name "*1_001.fq*" -o -name "*_1.fq.gz" \) | sort | \
    while read -r file; do

        sample=$(basename "$file" | sed -E 's/(_R1\..*|_R1_001\..*|_1\..*|_1_001\..*|\.R1\..*|\.R1_001\..*)//')
        R1_file=$(find "$INPUT_DIR" -type f -name "${sample}_R1*.fastq.gz" -o -name "${sample}_R1*.fq.gz" -o -name "${sample}_R1*.fq" -o -name "${sample}_R1*.fastq" -o -name "${sample}_1.fq.gz" | head -n 1)
        R2_file=$(find "$INPUT_DIR" -type f -name "${sample}_R2*.fastq.gz" -o -name "${sample}_R2*.fq.gz" -o -name "${sample}_R2*.fq" -o -name "${sample}_R2*.fastq" -o -name "${sample}_2.fq.gz" | head -n 1)

        if [ -z "$R1_file" ] || [ -z "$R2_file" ]; then
            echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 格式错误"
            exit 1
        else
            echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 分析开始"
        fi

        # 1. 创建单个样本输出目录结构
        mkdir -p $OUTPUT_DIR/tempdir/${sample}/fastp
        mkdir -p $OUTPUT_DIR/tempdir/${sample}/unicycler

        # 2. 二代双端数据质控
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 二代数据质控开始"
        docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $INPUT_DIR:$INPUT_DIR fastqcp:v1.0.0 \
        fastp -q 20 -u 40 -n 10 -i "$R1_file" -I "$R2_file" \
              -o "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}_R1.clean.fastq.gz" \
              -O "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}_R2.clean.fastq.gz" \
              -j "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}.json" \
              -h "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}.html" \
            >> "$OUTPUT_DIR/logdir/${sample}_1.log" 2>&1

        # 质控流程控制判断
        if [ -f "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}.html" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') $sample 二代数据质控完成"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') $sample 二代数据质控失败"
            exit 1
        fi

        # 3. 基因组组装
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 基因组组装开始"
        docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $INPUT_DIR:$INPUT_DIR unicycler:v0.5.1 \
        unicycler --short1 "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}_R1.clean.fastq.gz" \
                  --short2 "$OUTPUT_DIR/tempdir/${sample}/fastp/${sample}_R2.clean.fastq.gz" \
                  --min_fasta_length 1000 --threads $THREADS --kmers 77,99,111,121 \
                  --mode normal --out "$OUTPUT_DIR/tempdir/${sample}/unicycler" \
                >> "$OUTPUT_DIR/logdir/${sample}_2.log" 2>&1

        # 组装流程控制判断
        if [ -f "$OUTPUT_DIR/tempdir/${sample}/unicycler/assembly.fasta" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') $sample 基因组组装完成"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') $sample 基因组组装失败"
            exit 1
        fi

        # 4. 将组装结果复制到结果目录
        cp $OUTPUT_DIR/tempdir/${sample}/unicycler/assembly.fasta $OUTPUT_DIR/result/${sample}.fasta
        if [ -f "$OUTPUT_DIR/result/${sample}.fasta" ]; then
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') $sample 分析完成，结果文件已保存到 $OUTPUT_DIR/result/${sample}.fasta"
        else
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') $sample 分析失败"
        fi

    done


elif [ "$MODE" = "3" ]; then

    for sample_dir in "$INPUT_DIR"/* ; do
        [ -d "$sample_dir" ] || continue    
        sample=$(basename "$sample_dir")
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 分析开始"

        # 1. 创建单个样本输出目录结构
        mkdir -p $OUTPUT_DIR/tempdir/${sample}/nanostat
        mkdir -p $OUTPUT_DIR/tempdir/${sample}/chopper
        mkdir -p $OUTPUT_DIR/tempdir/${sample}/unicycler

        # 2. 判断是否是合并后的数据
        if [ "$FORMAT" = "Y" ]; then
            sample_data=$(ls "$sample_dir"/*)
        elif [ "$FORMAT" = "N" ]; then
            if ls "$sample_dir"/*.fastq.gz 2>/dev/null | grep -q .; then
                zcat "$sample_dir"/*.fastq.gz > ${OUTPUT_DIR}/tempdir/merged.fastq
                sample_data="${OUTPUT_DIR}/tempdir/merged.fastq"
            elif ls "$sample_dir"/*.fastq 2>/dev/null | grep -q .; then
                cat "$sample_dir"/*.fastq > ${OUTPUT_DIR}/tempdir/merged.fastq
                sample_data="${OUTPUT_DIR}/tempdir/merged.fastq"
            fi
        else
            echo "FORMAT参数必须为Y或N"
            exit 1
        fi

        # 3. NanoStat 与 chopper 进行质控
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 三代数据质控开始"
        docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $INPUT_DIR:$INPUT_DIR choppstat:v1.0.0 \
        NanoStat --name qc_report.txt --threads $THREADS --fastq $sample_data \
                 --outdir $OUTPUT_DIR/tempdir/${sample}/nanostat

        docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $INPUT_DIR:$INPUT_DIR choppstat:v1.0.0 \
        chopper --quality 7 --minlength 200 --headcrop 8 --tailcrop 8 \
                --trim-approach fixed-crop --threads $THREADS --input $sample_data \
                > "$OUTPUT_DIR/tempdir/${sample}/chopper/${sample}_clean.fastq" \
                2>> "$OUTPUT_DIR/logdir/${sample}_1.log"

        # 质控流程控制判断
        if [[ -s $OUTPUT_DIR/tempdir/${sample}/chopper/${sample}_clean.fastq ]]; then
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') $sample 三代数据质控成功"
        else
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') $sample 三代数据质控失败"
        fi

        # 4. 基因组组装
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $sample 基因组组装开始"
        docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $INPUT_DIR:$INPUT_DIR unicycler:v0.5.1 \
        unicycler --long $OUTPUT_DIR/tempdir/${sample}/chopper/${sample}_clean.fastq \
                  --min_fasta_length 1000 --threads $THREADS --kmers 77,99,111,121 \
                  --mode normal --out $OUTPUT_DIR/tempdir/${sample}/unicycler \
                  >> "$OUTPUT_DIR/logdir/${sample}_2.log" 2>&1

        # 组装流程控制判断
        if [ -f "$OUTPUT_DIR/tempdir/${sample}/unicycler/assembly.fasta" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') $sample 基因组组装完成"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') $sample 基因组组装失败"
            exit 1
        fi

        # 5. 将组装结果复制到结果目录
        cp $OUTPUT_DIR/tempdir/${sample}/unicycler/assembly.fasta $OUTPUT_DIR/result/${sample}.fasta
        if [ -f "$OUTPUT_DIR/result/${sample}.fasta" ]; then
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') $sample 分析完成，结果文件已保存到 $OUTPUT_DIR/result/${sample}.fasta"
        else
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') $sample 分析失败"
            exit 1
        fi

    done


elif [ "$MODE" = "23" ]; then

    # 检查参数是否提供
    if [ -z "$sample" ]; then
        echo "Usage: $0 -1 <R1_file> -2 <R2_file> -3 <R3_dir> -o <output_dir> -n <sample> -m 23"
        exit 1
    fi

    # 1. 创建单个样本输出目录结构
    mkdir -p $OUTPUT_DIR/tempdir/fastp
    mkdir -p $OUTPUT_DIR/tempdir/nanostat
    mkdir -p $OUTPUT_DIR/tempdir/chopper
    mkdir -p $OUTPUT_DIR/tempdir/unicycler

    # 2. 二代双端数据质控
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 二代数据质控开始"
    docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $SINGLE:$SINGLE -v $PAIR:$PAIR fastqcp:v1.0.0 \
    fastp -q 20 -u 40 -n 10 -i "$SINGLE" -I "$PAIR" \
          -o "$OUTPUT_DIR/tempdir/fastp/${sample}_R1.clean.fastq.gz" \
          -O "$OUTPUT_DIR/tempdir/fastp/${sample}_R2.clean.fastq.gz" \
          -j "$OUTPUT_DIR/tempdir/fastp/${sample}.json" \
          -h "$OUTPUT_DIR/tempdir/fastp/${sample}.html" \
        >> "$OUTPUT_DIR/logdir/${sample}_1.log" 2>&1

    if [ -f "$OUTPUT_DIR/tempdir/fastp/${sample}.html" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 二代数据质控完成"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 二代数据质控失败"
        exit 1
    fi

    # 2. 判断是否是合并后的数据
    sample_dir=$TGS/*  

    if [ "$FORMAT" = "Y" ]; then
        sample_data=$sample_dir/*
    elif [ "$FORMAT" = "N" ]; then
        if ls $sample_dir/*.fastq.gz 2>/dev/null | grep -q . ; then
            zcat $sample_dir/*.fastq.gz > ${OUTPUT_DIR}/tempdir/merged.fastq
            sample_data=${OUTPUT_DIR}/tempdir/merged.fastq
        elif ls $sample_dir/*.fastq 2>/dev/null | grep -q . ; then
            cat $sample_dir/*.fastq > ${OUTPUT_DIR}/tempdir/merged.fastq
            sample_data=${OUTPUT_DIR}/tempdir/merged.fastq
        fi
    else
        echo "FORMAT参数必须为Y或N"
        exit 1
    fi

    # 3. NanoStat 与 chopper 进行质控
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 三代数据质控开始"
    docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $TGS:$TGS choppstat:v1.0.0 \
    NanoStat --name qc_report.txt --threads $THREADS --fastq $sample_data \
             --outdir $OUTPUT_DIR/tempdir/nanostat

    docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR -v $TGS:$TGS choppstat:v1.0.0 \
    chopper --quality 7 --minlength 200 --headcrop 8 --tailcrop 8 \
            --trim-approach fixed-crop --threads $THREADS --input $sample_data \
            > "$OUTPUT_DIR/tempdir/chopper/${sample}_clean.fastq" \
            2>> "$OUTPUT_DIR/logdir/${sample}_2.log"

    # 质控流程控制判断
    if [[ -s $OUTPUT_DIR/tempdir/chopper/${sample}_clean.fastq ]]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 三代数据质控完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 三代数据质控失败"
        exit 1
    fi

    # 4. 基因组组装
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 基因组组装开始"
    docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR unicycler:v0.5.1 \
    unicycler --short1 "$OUTPUT_DIR/tempdir/fastp/${sample}_R1.clean.fastq.gz" \
              --short2 "$OUTPUT_DIR/tempdir/fastp/${sample}_R2.clean.fastq.gz" \
              --long "$OUTPUT_DIR/tempdir/chopper/${sample}_clean.fastq" \
              --min_fasta_length 1000 --threads $THREADS --kmers 77,99,111,121 \
              --mode normal --out "$OUTPUT_DIR/tempdir/unicycler" \
              >> "$OUTPUT_DIR/logdir/${sample}_3.log" 2>&1
 
    # 组装流程控制判断
    if [ -f "$OUTPUT_DIR/tempdir/unicycler/assembly.fasta" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 基因组组装完成"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 基因组组装失败"
        exit 1
    fi

    # 5. 将组装结果复制到结果目录
    cp $OUTPUT_DIR/tempdir/unicycler/assembly.fasta $OUTPUT_DIR/result/${sample}.fasta
    if [ -f "$OUTPUT_DIR/result/${sample}.fasta" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 分析完成，结果文件已保存到 $OUTPUT_DIR/result/${sample}.fasta"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 分析失败"
        exit 1
    fi

fi