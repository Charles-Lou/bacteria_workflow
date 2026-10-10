#!/bin/bash

<< EOF
需要的docker镜像 quast:v5.3.0 checkm2:v1.1.0

#脚本信息如下:
编辑人:娄成旭
说明:细菌基因组评估

#首次编辑
编辑时间: 2026.09.10
编辑说明:
1) 利用quast对基因组进行评估, 通过加入参考序列来计算覆盖度
2) 利用checkm2进行基因组评估, 查看完整度、污染度与杂合度

#二次编辑
编辑时间: 2026.09.24
编辑说明：
解决了checkm2在docker中运行时, 无法找到数据库的问题
解决quast在docker中运行时, 无法找到参考基因组的问题

EOF

while getopts "i:o:r:" opt; do
    case $opt in
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        r) REFERENCE=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir> -r <reference_genome>"
    exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "输入文件夹为空或不存在, 请检查输入文件夹路径是否正确"
    exit 1
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n"
echo -e "注! 这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式, 并去掉所有文件名中的空格与中文"
echo -e "注! 这是每次都会出现的第二个提示, 脚本使用quast(V5.3.0)进行基因组质量评估, 可以自定义参考基因组"
echo -e "注! 这是每次都会出现的第三个提示, 脚本使用checkm2(V1.1.0)进行基因组质量判定, 如发现异常, 立即更改或删除样本"
echo -e "注! 这是每次都会出现的第四个提示, quast地址: https://github.com/ablab/quast"
echo -e "注! 这是每次都会出现的第五个提示, checkm2地址: https://github.com/chklovski/CheckM2"

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

for file in "$INPUT_DIR"/*; do
    filesample=$(basename "$file" .fasta)

    mkdir -p $OUTPUT_DIR/tempDir/$filesample/quast

    if [ -z "$REFERENCE" ]; then
        # 2. quast基因组质量评估流程
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $filesample 基因组组装质量评估开始"
        docker run --rm  -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR quast:v5.3.0 \
        quast --threads 24 --min-contig 1000 --output-dir $OUTPUT_DIR/tempDir/$filesample/quast $file \
            >> $OUTPUT_DIR/logDir/${filesample}_quast.log 2>&1

        cp $OUTPUT_DIR/tempDir/$filesample/quast/report.tsv $OUTPUT_DIR/result/${filesample}_quast_report.tsv
    else
        # 2. quast基因组质量评估流程
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $filesample 基因组组装质量评估开始"
        docker run --rm  -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR -v $REFERENCE:$REFERENCE quast:v5.3.0 \
        quast -r $REFERENCE --threads 24 --min-contig 1000 --output-dir $OUTPUT_DIR/tempDir/$filesample/quast $file \
            >> $OUTPUT_DIR/logDir/${filesample}_quast.log 2>&1

        cp $OUTPUT_DIR/tempDir/$filesample/quast/report.tsv $OUTPUT_DIR/result/${filesample}_quast_report.tsv    
    fi

    if [ -f "$OUTPUT_DIR/result/${filesample}_quast_report.tsv" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $filesample 基因组组装质量评估完成, 结果已存入 $OUTPUT_DIR/result/"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') $filesample 基因组组装质量评估失败"
        exit 1
    fi

done

# 3. checkm2基因组质量检测流程
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 基因组完整度及污染度评估开始"
mkdir -p $OUTPUT_DIR/tempDir/checkm2

docker run --rm  -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR checkm2:v1.1.0 \
checkm2 predict --input $INPUT_DIR --output-directory $OUTPUT_DIR/tempDir/checkm2 \
                    -x .fasta --force --threads 24 --database_path /data/uniref100.KO.1.dmnd \
                    >> $OUTPUT_DIR/logDir/checkm2.log 2>&1

cp $OUTPUT_DIR/tempDir/checkm2/quality_report.tsv $OUTPUT_DIR/result/checkm2_report.tsv

if [ -f "$OUTPUT_DIR/result/checkm2_report.tsv" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') 基因组完整度及污染度评估成功, 结果已存入 $OUTPUT_DIR/result/checkm2_report.tsv"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') 基因组完整度及污染度评估失败"
    exit 1
fi