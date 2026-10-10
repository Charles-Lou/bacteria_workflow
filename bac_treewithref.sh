#!/bin/bash

<< EOF
需要的docker镜像 ksnp:v4.1

#脚本信息如下:
编辑人:娄成旭
说明:细菌无参建树流程

#首次编辑
编辑时间: 2025.02.23
编辑说明:
一、正确识别输入文件夹内的所有文件后缀是否为fasta,如果不是,直接报错并退出,提示"xxx文件不是fasta格式,请修改后重新分析"
二、本次共分析文件数为xxx,文件格式识别通过,开始进行无参建树
三、使用kSNP4.1进行无参建树的过程

# 二次编辑
编辑时间: 2025.02.27
编辑说明:
一、创建软件标准输入文件
二、判断最佳 K 值
三、得到全部以及核心snp,分别并建树(ML MP NJ)
四、判断无参建树是否成功
五、解决Kchooser4运行时的文件位置

# 三次编辑
编辑时间: 2025.03.03
编辑说明: 完善控制流程

# 四次编辑
编辑时间: 2025.07.07
编辑说明: 完善部分警告、提醒以及版本信息

# 五次编辑
编辑时间: 2025.08.08
编辑说明: 完善流程与格式、控制log输出

# 六次编辑
编辑时间: 2026.02.24
编辑说明: 改变了镜像命名规则

# 七次编辑
编辑时间: 2026.03.19
编辑说明: 增加了基因组质量检测功能
EOF

while getopts "i:o:c:" opt; do
    case $opt in
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        c) CHECK=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir> -c Y/N "
    exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "Error: Input directory is empty or does not exist."
    exit 1
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n注! 这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式, 并去掉所有文件名中的空格与中文"

echo -e "\n注! 这是每次都会出现的第二个提示, 脚本使用checkm2(V1.1.0)进行基因组质量判定, 如发现异常, 立即更改或删除样本"

echo -e "\n注! 这是每次都会出现的第三个提示, 脚本使用kSNP(V4.1)进行无参建树分析"

echo -e "\n注! 这是每次都会出现的第四个提示, checkm2地址: https://github.com/chklovski/CheckM2"

echo -e "\n注! 这是每次都会出现的第五个提示, kSNP地址: https://sourceforge.net/projects/ksnp/"

# 0. 创建项目输出目录 
mkdir -p $OUTPUT_DIR/logDir
mkdir -p $OUTPUT_DIR/tempDir
mkdir -p $OUTPUT_DIR/result

# 1. 文件后缀判断及文件数量统计
file_count=0
for file in "$INPUT_DIR"/*; do
    filename=$(basename "$file")

    if [[ ! "$filename" == *.fasta ]]; then
        echo "文件 $filename 后缀非fasta,请修改文件名后重试。"
        exit 1
    fi

    if [[ "$filename" == *" "* ]]; then
        echo "文件 $filename 中包含空格,请修改文件名后重试。"
        exit 1
    fi

    ((file_count++))

done

echo -e "\n输入文件夹中共有 $file_count 个文件"


if [ "$CHECK" = "Y" ]; then

    # 2. 基因组质量检测流程
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 基因组质量检测开始"

    docker run --rm  -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR checkm2:v1.1.0 \
    checkm2 predict --quiet --input $INPUT_DIR --output-directory $OUTPUT_DIR/tempDir/ \
    -x .fasta --force --threads 24 --database_path uniref100.KO.1.dmnd

    cp $OUTPUT_DIR/tempDir/quality_report.tsv $OUTPUT_DIR/result/quality_report.tsv

    # 基因组质量检测判断
    if [[ -s $OUTPUT_DIR/result/quality_report.tsv ]] ; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 基因组质量检测成功, 结果已存入 $OUTPUT_DIR/tempDir"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 基因组质量检测失败, 请检查"
        exit 1
    fi

elif [ "$CHECK" = "N" ]; then

    # 3. 计算 K 值流程
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 计算最佳K值开始"

    # 创建软件标准输入文件
    docker run --rm -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR ksnp:v4.1 \
    MakeKSNP4infile -indir $INPUT_DIR -outfile $OUTPUT_DIR/tempDir/Myinfile

    # 计算最佳 K 值
    docker run --rm -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR ksnp:v4.1 \
    bash -c "cd $OUTPUT_DIR/tempDir && Kchooser4 -in ./Myinfile >> $OUTPUT_DIR/logDir/1.log 2>&1"

    # 拿到最佳 K 值
    BEST_K=$(grep "The optimum value of k is" $OUTPUT_DIR/tempDir/Kchooser4_.report | awk '{print $7}')

    # 计算最佳 K 值流程判断
    if [[ -s $OUTPUT_DIR/tempDir/Kchooser4_.report ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 计算最佳K值成功, 最佳K值为 $BEST_K " 
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 计算最佳K值失败, 请检查"
    fi

    # 4. 无参建树流程
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 无参建树流程开始" 

    # 无参建树
    docker run --rm  -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR ksnp:v4.1 \
    kSNP4 -in $OUTPUT_DIR/tempDir/Myinfile \
        -outdir $OUTPUT_DIR/tempDir \
        -k $BEST_K -ML -NJ -vcf -core \
        >> $OUTPUT_DIR/logDir/2.log 2>&1

    # 复制文件到结果文件夹
    cp $OUTPUT_DIR/tempDir/tree.core_SNPs.ML.tre $OUTPUT_DIR/tempDir/tree.core_SNPs.NJ.tre $OUTPUT_DIR/tempDir/tree.SNPs_all.ML.tre $OUTPUT_DIR/tempDir/tree.SNPs_all.NJ.tre $OUTPUT_DIR/result

    # 无参建树流程判断
    if [[ -s $OUTPUT_DIR/result/tree.core_SNPs.NJ.tre ]] ; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 无参建树流程成功, 结果已存入 $OUTPUT_DIR/tempDir"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 无参建树流程失败, 请检查"
        exit 1
    fi

else
    echo "$(date '+%Y-%m-%d %H:%M:%S') 参数输入错误, 请检查"
    exit 1
fi