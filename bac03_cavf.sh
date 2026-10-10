#!/bin/bash

<< EOF
需要的docker镜像: abricate:v1.2

#脚本信息如下:
编辑人:娄成旭
说明:

#首次编辑
编辑时间: 2026.09.24
编辑说明: 利用abricate进行耐药基因与毒力基因分析

EOF

while getopts "i:o:d:c:" opt; do
    case $opt in
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        d) IDENTITY=$OPTARG ;;
        c) COVERAGE=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir> -t <threads>"
    exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "警告: 输入文件夹件夹为空或不存在，请检查输入文件夹路径"
    exit 1
fi

# 设置IDENTITY和coverage的默认值为90
if [ -z "$IDENTITY" ]; then
	IDENTITY=90
else
    echo -e "\n注!一致性(identity)阈值已设置为 $IDENTITY"
fi

if [ -z "$COVERAGE" ]; then
	COVERAGE=90
else
    echo -e "\n注!覆盖度(coverage)阈值已设置为 $COVERAGE"
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n"
echo -e "注!这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式, 并去掉所有文件名中的空格与中文"
echo -e "注!这是每次都会出现的第二个提示, abricate参数: 覆盖度与一致性默认均为90, 进行card、vfdb、plasmidfinder预测生成01矩阵"
echo -e "注!这是每次都会出现的第三个提示, abricate地址: https://github.com/tseemann/abricate"

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


# 2.1 耐药(CARD)基因预测
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 耐药基因(CARD)预测开始"

mkdir -p $OUTPUT_DIR/card/tab
mkdir -p $OUTPUT_DIR/card/bed
mkdir -p $OUTPUT_DIR/card/fasta

docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $INPUT_DIR && \
for file in $INPUT_DIR/*.fasta ; do 
    filename=\$(basename \$file .fasta)
    abricate --quiet --THREADS 24 --db card --minid $IDENTITY --mincov $COVERAGE \
             \${filename}.fasta > $OUTPUT_DIR/card/tab/\${filename}_card.tab
done"

# 2.2 生成耐药基因(CARD)矩阵
docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $OUTPUT_DIR/card/tab && abricate --quiet --summary --identity *.tab > 1AMatrix_card.tab"

# 2.3 生成bed文件，并提取fasta文件
docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "
for file in $INPUT_DIR/*.fasta ; do
    filename=\$(basename \$file .fasta)
    tail -n +2 $OUTPUT_DIR/card/tab/\${filename}_card.tab | cut -f2-4 > $OUTPUT_DIR/card/bed/\${filename}_card.bed
    bedtools getfasta -bed $OUTPUT_DIR/card/bed/\${filename}_card.bed -fi \$file -fo $OUTPUT_DIR/card/fasta/\${filename}_card.fasta 
done
"

# 2.4 检查耐药基因(CARD)预测结果
if [[ -s $OUTPUT_DIR/card/tab/1AMatrix_card.tab ]] ;then
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') 耐药基因(CARD)预测成功"
else
	echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 耐药基因(CARD)预测失败"
    exit 1
fi


# 3.1 毒力(VFDB)基因预测
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 毒力基因(VFDB)预测开始"

mkdir -p $OUTPUT_DIR/vfdb/tab
mkdir -p $OUTPUT_DIR/vfdb/bed
mkdir -p $OUTPUT_DIR/vfdb/fasta

docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $INPUT_DIR && \
for file in $INPUT_DIR/*.fasta ; do 
    filename=\$(basename \$file .fasta)
    abricate --quiet --THREADS 24 --db vfdb --minid $IDENTITY --mincov $COVERAGE \
             \${filename}.fasta > $OUTPUT_DIR/vfdb/tab/\${filename}_vfdb.tab
done"

# 3.2 生成毒力基因(VFDB)矩阵
docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $OUTPUT_DIR/vfdb/tab && abricate --quiet --summary --identity *.tab > 1AMatrix_vfdb.tab"

# 3.3 生成bed文件，并提取fasta文件
docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "
for file in $INPUT_DIR/*.fasta ; do
    filename=\$(basename \$file .fasta)
    tail -n +2 $OUTPUT_DIR/vfdb/tab/\${filename}_vfdb.tab | cut -f2-4 > $OUTPUT_DIR/vfdb/bed/\${filename}_vfdb.bed
    bedtools getfasta -bed $OUTPUT_DIR/vfdb/bed/\${filename}_vfdb.bed -fi \$file -fo $OUTPUT_DIR/vfdb/fasta/\${filename}_vfdb.fasta 
done
"

# 3.4 检查毒力基因(VFDB)预测结果
if [[ -s  $OUTPUT_DIR/vfdb/tab/1AMatrix_vfdb.tab ]] ;then
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') 毒力基因(VFDB)预测成功"
else
	echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 毒力基因(VFDB)预测失败"
    exit 1
fi


# 4.1 质粒(plasmidfinder)预测
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 质粒(plasmidfinder)预测开始"

mkdir -p $OUTPUT_DIR/plasmidfinder/tab
mkdir -p $OUTPUT_DIR/plasmidfinder/bed
mkdir -p $OUTPUT_DIR/plasmidfinder/fasta

docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $INPUT_DIR && \
for file in $INPUT_DIR/*.fasta ; do 
    filename=\$(basename \$file .fasta)
    abricate --quiet --THREADS 24 --db plasmidfinder --minid $IDENTITY --mincov $COVERAGE \
             \${filename}.fasta > $OUTPUT_DIR/plasmidfinder/tab/\${filename}_plasmidfinder.tab
done"

# 4.2 生成质粒(plasmidfinder)矩阵
docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $OUTPUT_DIR/plasmidfinder/tab && abricate --quiet --summary --identity *.tab > 1AMatrix_plasmidfinder.tab"

# 4.3 检查质粒(plasmidfinder)预测结果
if [[ -s $OUTPUT_DIR/plasmidfinder/tab/1AMatrix_plasmidfinder.tab ]] ;then
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') 质粒(plasmidfinder)预测成功"
else
	echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 质粒(plasmidfinder)预测失败"
    exit 1
fi


# 5.1 耐药(NCBI)基因预测
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 耐药基因(NCBI)预测开始"

mkdir -p $OUTPUT_DIR/ncbi/tab
mkdir -p $OUTPUT_DIR/ncbi/bed
mkdir -p $OUTPUT_DIR/ncbi/fasta

docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $INPUT_DIR && \
for file in $INPUT_DIR/*.fasta ; do 
    filename=\$(basename \$file .fasta)
    abricate --quiet --THREADS 24 --db ncbi --minid $IDENTITY --mincov $COVERAGE \
             \${filename}.fasta > $OUTPUT_DIR/ncbi/tab/\${filename}_ncbi.tab
done"

# 5.2 生成耐药基因(NCBI)矩阵
docker run --rm -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "cd $OUTPUT_DIR/ncbi/tab && abricate --quiet --summary --identity *.tab > 1AMatrix_ncbi.tab"

# 5.3 生成bed文件，并提取fasta文件
docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR abricate:v1.2 \
bash -c "
for file in $INPUT_DIR/*.fasta ; do
    filename=\$(basename \$file .fasta)
    tail -n +2 $OUTPUT_DIR/ncbi/tab/\${filename}_ncbi.tab | cut -f2-4 > $OUTPUT_DIR/ncbi/bed/\${filename}_ncbi.bed
    bedtools getfasta -bed $OUTPUT_DIR/ncbi/bed/\${filename}_ncbi.bed -fi \$file -fo $OUTPUT_DIR/ncbi/fasta/\${filename}_ncbi.fasta 
done
"

# 5.4 检查耐药基因(NCBI)预测结果
if [[ -s $OUTPUT_DIR/ncbi/tab/1AMatrix_ncbi.tab ]] ;then
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') 耐药基因(NCBI)预测成功"
else
	echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 耐药基因(NCBI)预测失败"
    exit 1
fi
