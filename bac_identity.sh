#!/bin/bash

<< EOF
#脚本信息如下:
编辑人:娄成旭
说明:ITS物种鉴定

#首次编辑
编辑时间: 2026.06.17
编辑说明: ITS数据库比对并整理结果

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
    echo "用法: $0 -i <input_dir> -o <output_dir> -t <threads>"
    exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "警告：输入文件夹为空或不存在,检查后重试"
    exit 1
fi

# 设置THREADS的默认值为24
if [ -z "$THREADS" ]; then
    THREADS=24
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n注! 这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式,并去掉所有文件名中的空格与中文"

echo -e "\n注! 这是每次都会出现的第二个提示, 请去掉序列的title中的中文、空格、点、冒号等特殊字符(下划线除外),tree文件中的叶子名称为序列title名而非文件名"

echo -e "\n注! 这是每次都会出现的第三个提示, 请把所有fasta文件中的“-”及“.”改为“N”, 保证序列中只有AGCTN,保证格式的标准"

echo -e "\n注! 这是每次都会出现的第四个提示, 脚本首先使用balst(v2.17.0)进行数据库对比,随后使用python脚本进行结果整理"

echo -e "\n注! 这是每次都会出现的第五个提示, blast地址: https://github.com/JacobLondon/Blastn"

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
        exit 1
    fi

    if [[ "$filename" == *" "* ]]; then
        echo "文件 $filename 中包含空格,请修改文件名后重试。"
        exit 1
    fi

    ((file_count++))
    
done

echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 输入文件夹中共有 $file_count 个文件"

for file in $INPUT_DIR/*.fasta ; do
    filename=$(basename $file .fasta)

    # 2. 数据比对
    docker run --rm -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:/$OUTPUT_DIR its:v2024 \
    blastn -db /database/unite2024ITS.fasta \
           -query $file -outfmt 6 -num_threads $THREADS \
           -out $OUTPUT_DIR/tempdir/$filename.blast.txt

    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $filename 数据比对完成"

    # 3. 数据合并
    docker run --rm -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:/$OUTPUT_DIR its:v2024 \
    python merge.py $OUTPUT_DIR/tempdir/$filename.blast.txt /unite2024ITS.classification $OUTPUT_DIR/tempdir/$filename.combined.txt

    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename 数据合并完成"

    # 4. 复制结果文件到结果文件夹
    cp $OUTPUT_DIR/tempdir/$filename.combined.txt $OUTPUT_DIR/result/$filename.result.txt

    if [ -s "$OUTPUT_DIR/result/$filename.result.txt" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename 数据分析完成, 结果已保存到 $OUTPUT_DIR/result"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename 数据分析失败"
        exit 1
    fi

done