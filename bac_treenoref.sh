#!/bin/bash

<< EOF
需要的docker镜像 reftree:v2.1.4; virsnp:v4.6.0; virtree:1.0; gubbins:v3.4

#脚本信息如下:
编辑人:娄成旭
说明:有参建树（适用于基因组亲缘关系较近的分析）

#首次编辑
编辑时间: 2025.04.03
编辑说明: 摒弃Snippy,利用parsnp进行有参建树

#二次编辑
编辑时间: 2025.05.08
编辑说明: 加入了一些提示和运行失败提示

#三次编辑
编辑时间: 2025.05.16
编辑说明: 完善部分警告和提醒,以及版本信息

#四次编辑
编辑时间: 2025.05.20
编辑说明: 加入了snippy的分析流程

#五次编辑
编辑时间: 2025.08.25
编辑说明: 完善结构与流程
1) 完善文件夹结构并加入文件整理
2) 完善日志, 加入顺序方便统计
3) 完善gubbins命令, 流程更加完善
4) 解决变异矩阵为空的问题, 变异矩阵为snippy核心基因组snp, 不是清理后也不是去重组后(使用core.aln而非clean.full.aln与clean.core.aln)
5) 完善结果文件夹, 将重要数据放入result文件夹, 方便查找

EOF

while getopts "i:o:r:t:" opt; do
    case $opt in
        i) INPUT_DIR=$OPTARG ;;
        o) OUTPUT_DIR=$OPTARG ;;
        r) REF=$OPTARG ;;
        t) THREADS=$OPTARG ;;
    esac
done

# 检查参数是否提供
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 -i <input_dir> -o <output_dir> -r <reference> -t <threads>"
    exit 1
fi

# 检查输入文件夹是否为空
if [ ! -d "$INPUT_DIR" ] || [ "$(ls -A "$INPUT_DIR")" = "" ]; then
    echo "警告: 输入文件夹件夹为空或不存在，请检查输入文件夹路径"
    exit 1
fi

# 设置THREADS的默认值为32
if [ -z "$THREADS" ]; then
    THREADS=32
fi

# 判断是否自定义参考序列
if [ -z "$REF" ]; then
    echo "警告: 没有提供参考序列"
    exit 1
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式, 并去掉所有文件名中的空格与中文"

echo -e "\n这是每次都会出现的第二个提示, 请把所有fasta文件中的“-”改为“N”, 保证序列中只有AGCTN,否则必然报错"

echo -e "\n这是每次都会出现的第三个提示, -r后面跟随的参考序列只能是fasta格式(.fasta)"

echo -e "\n这是每次都会出现的第四个提示, 脚本使用使用parsnp(V2.1.4)与snippy(4.6.0)两种方法进行有参核心基因组建树分析"

echo -e "\n这是每次都会出现的第五个提示, parsnp地址: https://github.com/marbl/parsnp; snippy地址: https://github.com/tseemann/snippy"

# 0. 建立文件夹
mkdir -p "$OUTPUT_DIR/logdir"
mkdir -p "$OUTPUT_DIR/result"
mkdir -p "$OUTPUT_DIR/tempdir"
mkdir -p "$OUTPUT_DIR/tempdir/snippy"

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


echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') parsnp分析流程开始"

# 2.1 parsnp分析流程
docker run --rm -v $REF:$REF -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR reftree:v2.1.4 \
parsnp -c -x --vcf -n mafft -r $REF -d $INPUT_DIR/* -o $OUTPUT_DIR/tempdir/parsnp -p $THREADS 2>> $OUTPUT_DIR/logdir/1_parsnp.log

# 2.2 复制文件到结果文件夹
cp $OUTPUT_DIR/tempdir/parsnp/parsnp.tree $OUTPUT_DIR/result/parsnp.tree

if [[ -s $OUTPUT_DIR/result/parsnp.tree ]]; then
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') parsnp分析流程完成"
else
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') parsnp分析流程失败"
    exit 1
fi


echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') snippy分析流程开始"

# 3.1 snippy call snp流程
for file in "$INPUT_DIR"/*; do
    filename=$(basename $file .fasta)

    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $filename 分析开始"

    # 运行snippy
    docker run --rm -v $REF:$REF -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR virsnp:v4.6.0 \
    snippy --outdir $OUTPUT_DIR/tempdir/snippy/$filename --cpus $THREADS --reference $REF --ctgs $file --report --quiet > $OUTPUT_DIR/logdir/2_snippy_snp.log 2>&1

    if [ -f $OUTPUT_DIR/tempdir/snippy/$filename/snps.report.txt ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') $filename 分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 分析失败,请检查文件"
        exit 1
    fi

done

# 3.2 snippy 提取核心基因组流程
docker run --rm -v $REF:$REF -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR virsnp:v4.6.0 \
bash -c "cd $OUTPUT_DIR/tempdir/snippy && snippy-core --ref $REF --prefix core * > $OUTPUT_DIR/logdir/3_snippy_core.log 2>&1" 

# 3.3 snippy 清理步骤
docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR virsnp:v4.6.0 \
snippy-clean_full_aln $OUTPUT_DIR/tempdir/snippy/core.full.aln > $OUTPUT_DIR/tempdir/snippy/clean.full.aln

# 3.4 gubbins 去重组
docker run --rm -v $REF:$REF -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR gubbins:v3.4 \
/bin/bash -c "cd $OUTPUT_DIR/tempdir/snippy && run_gubbins.py -p gubbins clean.full.aln > $OUTPUT_DIR/logdir/4_gubbins.log"

# 3.5 snippy 提取核心SNP位点
docker run --rm -v $REF:$REF -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR virsnp:v4.6.0 \
/bin/bash -c "cd $OUTPUT_DIR/tempdir/snippy && snp-sites -c $OUTPUT_DIR/tempdir/snippy/gubbins.filtered_polymorphic_sites.fasta > clean.core.aln"

# 3.6 iqtree建树
docker run --rm -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:/$OUTPUT_DIR virtree:1.0 \
/bin/bash -c "cd $OUTPUT_DIR/tempdir/snippy && iqtree -s ./clean.core.aln -T $THREADS -m MFP -B 1000 -bnni > $OUTPUT_DIR/logdir/5_virtree.log"

#3.7 获得snp数量矩阵
docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR virsnp:v4.6.0 \
/bin/bash -c "cd $OUTPUT_DIR/tempdir/snippy/ && snp-dists ./core.aln > core.aln.matrix.tsv 2> $OUTPUT_DIR/logdir/6_snp-dists.log"

#3.8 复制结果文件到结果目录
cp $OUTPUT_DIR/tempdir/snippy/clean.core.aln.treefile $OUTPUT_DIR/result/snippy.treefile
cp $OUTPUT_DIR/tempdir/snippy/core.aln.matrix.tsv $OUTPUT_DIR/result/core.aln.matrix.tsv

#3.9 整理文件夹
docker run --rm -v $INPUT_DIR:/$INPUT_DIR -v $OUTPUT_DIR:/$OUTPUT_DIR virtree:1.0 \
/bin/bash -c "cd $OUTPUT_DIR/tempdir/snippy && mkdir 1Acore 1Agubbins 1Atree && mv ./core* ./1Acore && mv ./gubbins* ./1Agubbins && mv ./clean* ./1Atree"


if [ -f "$OUTPUT_DIR/result/snippy.treefile" ]; then
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') snippy分析流程完成"
else
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') snippy分析流程失败"
    exit 1
fi
