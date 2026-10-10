#!/bin/bash

<< EOF
需要的docker镜像: mist:v1.2.0

#脚本信息如下:
编辑人: 娄成旭
说明: 对任何有方案物种进行mlst及cgmlst分型

#首次编辑
编辑时间: 2026.04.23
编辑说明: 完成分型及结果整理, 后续考虑加入下载数据库及构建索引功能

#二次编辑
编辑说明: 2026.04.24
编辑说明: 完善表头, 加入更多可以辅助判断的结果

EOF

while getopts "i:o:d:" opt; do
    case $opt in
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        d) DATABASE=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ] || [ -z "$DATABASE" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir> -d <database>"
    exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "警告: 输入文件夹件夹为空或不存在，请检查输入文件夹路径"
    exit 1
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n注!这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式,并去掉所有文件名中的空格与中文"

echo -e "\n注!这是每次都会出现的第二个提示, 脚本使用Mist(一致性默认为99)进行(cg)MLST分型,并生成结果矩阵"

echo -e "\n注!这是每次都会出现的第三个提示, Mist地址: https://github.com/BioinformaticsPlatformWIV-ISP/MiST"

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

# 2. 对每个样本进行 (cg)MLST 分型
echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') (cg)MLST分型开始"

docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR -v $DATABASE:$DATABASE mist:v1.3.0 \
bash -c "cd $INPUT_DIR && \
for file in \$(ls "$INPUT_DIR"/*.fasta | sort) ; do
    filename=\$(basename \$file .fasta)
    mist call --db $DATABASE --fasta \$file -t 32 \
              --out-dir $OUTPUT_DIR/tempDir/\$filename/ \
              --out-tsv $OUTPUT_DIR/tempDir/\$filename/\$filename.tsv \
              --sample-id \$filename > $OUTPUT_DIR/logDir/\$filename.log 2>&1

    #生成第一列
    echo -e \"Sample\n\$filename\" > $OUTPUT_DIR/tempDir/\$filename/1row.tsv
    
    #生成第二列
    st=\$(grep -oP '(?<=Matching ST: )\d+' $OUTPUT_DIR/logDir/\$filename.log)
    echo -e \"(cg)MLST\n\$st\" > $OUTPUT_DIR/tempDir/\$filename/2row.tsv

    #生成第三列
    match=\$(grep -oP '(?<=Detected ).*?(?= loci)' $OUTPUT_DIR/logDir/\$filename.log)
    echo -e \"Match\n\$match\" > $OUTPUT_DIR/tempDir/\$filename/3row.tsv

    #生成第四列
    rate=\$(grep -oP '(?<=loci \().*?(?=\), including)' $OUTPUT_DIR/logDir/\$filename.log)
    echo -e \"Rate\n\$rate\" > $OUTPUT_DIR/tempDir/\$filename/4row.tsv 

    #生成第五列
    novel=\$(grep -oP '(?<=including )\d+(?= \(potential\))' $OUTPUT_DIR/logDir/\$filename.log)
    echo -e \"Novel\n\$novel\" > $OUTPUT_DIR/tempDir/\$filename/5row.tsv

    #生成后面的具体locus 与 allele
    sed '1,2d' $OUTPUT_DIR/tempDir/\$filename/\$filename.tsv > $OUTPUT_DIR/tempDir/\$filename/temp1.tsv
    awk '{print \$1}' $OUTPUT_DIR/tempDir/\$filename/temp1.tsv | paste -sd'\t' - > $OUTPUT_DIR/tempDir/\$filename/temp2.tsv
    awk '{print \$2}' $OUTPUT_DIR/tempDir/\$filename/temp1.tsv | paste -sd'\t' - > $OUTPUT_DIR/tempDir/\$filename/temp3.tsv
    cat $OUTPUT_DIR/tempDir/\$filename/temp2.tsv $OUTPUT_DIR/tempDir/\$filename/temp3.tsv > $OUTPUT_DIR/tempDir/\$filename/6row.tsv

    #生成最终结果文件
    paste $OUTPUT_DIR/tempDir/\$filename/1row.tsv $OUTPUT_DIR/tempDir/\$filename/2row.tsv $OUTPUT_DIR/tempDir/\$filename/3row.tsv \
          $OUTPUT_DIR/tempDir/\$filename/4row.tsv $OUTPUT_DIR/tempDir/\$filename/5row.tsv $OUTPUT_DIR/tempDir/\$filename/6row.tsv \
          > $OUTPUT_DIR/tempDir/\$filename/result.tsv

    #删除临时文件
    rm $OUTPUT_DIR/tempDir/\$filename/temp1.tsv $OUTPUT_DIR/tempDir/\$filename/temp2.tsv $OUTPUT_DIR/tempDir/\$filename/temp3.tsv
    rm $OUTPUT_DIR/tempDir/\$filename/1row.tsv $OUTPUT_DIR/tempDir/\$filename/2row.tsv $OUTPUT_DIR/tempDir/\$filename/3row.tsv \
       $OUTPUT_DIR/tempDir/\$filename/4row.tsv $OUTPUT_DIR/tempDir/\$filename/5row.tsv $OUTPUT_DIR/tempDir/\$filename/6row.tsv

    #合并结果
    cat $OUTPUT_DIR/tempDir/\$filename/result.tsv >> $OUTPUT_DIR/result/result.tsv

done"

# 3. 整理结果
sed -i '3~2d' $OUTPUT_DIR/result/result.tsv
if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') (cg)MLST分型成功"
else
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') (cg)MLST分型失败"
fi
