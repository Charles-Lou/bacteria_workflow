#!/bin/bash

<< EOF
脚本信息如下:
需要的docker镜像: seqsero:v1.3.1、kaptive:v3.1.0、emmtyper:v1.0、pneumo_type:v2.0.1、ssuis:v1.0、meningotype:v0.8.5、choleraefinder:v1.0

编辑人:娄成旭

#首次编辑
编辑时间:2026.01.21
编辑说明:实现沙门氏菌、肺炎克雷伯菌、鲍曼不动杆菌、副溶血弧菌血清型分型, 以及A族链球菌emm分型

#二次编辑
编辑时间:2026.02.01
编辑说明:完善分析完成的判断机制, 完善提示信息

#三次编辑
编辑时间:2026.02.12
编辑说明:增加肺炎链球菌的血清型, ST分型

#四次编辑
编辑时间:2026.03.02
编辑说明:增加脑膜炎奈瑟菌血清群分析(不完美, 后边官方更新后还要改)

#五次编辑
编辑时间:20226.03.04
编辑说明:增加猪链的分析流程

#六次编辑
编辑时间:2026.03.06
编辑说明:增加霍乱弧菌分析流程

EOF

# 定义输入输出文件夹和物种
while getopts "i:o:s:" opt; do
    case $opt in
        i) INPUT_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        s) SPECIES="$OPTARG" ;;
    esac
done

# 检查输入输出文件夹与物种名是否存在
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "usage: $0 -i <INPUT_DIR> -o <OUTPUT_DIR> -s sal/klb/ab/vp/gas/sp/ss/nm/vc"
    exit 1
fi

# 去掉输入输出文件夹路径末尾的斜杠确保后续流程无误
INPUT_DIR=$(echo "$INPUT_DIR" | sed 's:/*$::')
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's:/*$::')

echo -e "\n注! 这是每次都会出现的第一个提示, 请检查所有的文件是否为fasta格式, 并去掉所有文件名中的空格与中文"

echo -e "\n注! 这是每次都会出现的第二个提示, 请把所有fasta文件中的“-”及“.”改为“N”, 保证序列中只有AGCTN"

echo -e "\n注! 这是每次都会出现的第三个提示, 脚本使用emmtyper(v0.2.0)进行emm分型, 地址: https://github.com/MDU-PHL/emmtyper"

echo -e "\n注! 这是每次都会出现的第五个提示, 脚本使用SeqSero2(V1.3.2)进行沙门氏菌血清型分型, 地址: https://github.com/denglab/SeqSero2"

echo -e "\n注! 这是每次都会出现的第四个提示, 脚本使用Pneumo_Typer(v2.0.1)进行肺炎链球菌血清型分型, 地址: https://github.com/Xiangyang1984/Pneumo-Typer"

echo -e "\n注! 这是每次都会出现的第六个提示, 脚本使用Kaptive(v3.1)进行克雷伯,副溶血及鲍曼不动杆菌的血清型分析, 地址: https://github.com/klebgenomics/Kaptive"

echo -e "\n注! 这是每次都会出现的第七个提示, 脚本使用SsuisChara(v2.0.0)进行猪链球菌分析, 地址: https://github.com/guogenglin/SsuisChara"

echo -e "\n注! 这是每次都会出现的第八个提示, 脚本使用meningotype(v0.8.5)进行脑膜炎奈瑟菌血清群分析, 地址: https://github.com/MDU-PHL/meningotype"

echo -e "\n注! 这是每次都会出现的第九个提示, 当结果出现歧义, 需要依靠tempdir中的文件进行辅助判断"


# 创建输出目录结构
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


# 2. 沙门氏菌血清型分析
if [ "$SPECIES" = "sal" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 沙门氏菌血清型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR seqsero:v1.3.1 \
    bash -c " cp /head.tsv $OUTPUT_DIR/result/result.tsv && cd $OUTPUT_DIR/tempdir

    for file in $INPUT_DIR/*.fasta ; do 
        filename=\$(basename \$file .fasta)

        SeqSero2_package.py -d \$filename -m k -t 4 -p 24 -i \$file >> $OUTPUT_DIR/logdir/seqsore.log 2>&1
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}/SeqSero_result.tsv >> $OUTPUT_DIR/result/result.tsv

    done
    "

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 沙门氏菌血清型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 沙门氏菌血清型分析失败"
    fi

# 3. 肺炎克雷伯菌血清型分析
elif [ "$SPECIES" = "klb" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 肺炎克雷伯菌血清型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR kaptive:v3.1.0 \
    bash -c " cp /head.tsv $OUTPUT_DIR/result/result.tsv

    for file in $INPUT_DIR/*.fasta ; do 
        filename=\$(basename \$file .fasta)

        kaptive assembly /database/Klebsiella_k_locus_primary_reference.gbk \$file -o $OUTPUT_DIR/tempdir/\${filename}_k.tsv
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}_k.tsv >> $OUTPUT_DIR/result/result.tsv

        kaptive assembly /database/Klebsiella_o_locus_primary_reference.gbk \$file -o $OUTPUT_DIR/tempdir/\${filename}_o.tsv
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}_o.tsv >> $OUTPUT_DIR/result/result.tsv

    done
    "

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 肺炎克雷伯菌血清型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 肺炎克雷伯菌血清型分析失败"
    fi

# 4. 鲍曼不动杆菌血清型分析
elif [ "$SPECIES" = "ab" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 鲍曼不动杆菌血清型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR kaptive:v3.1.0 \
    bash -c " cp /head.tsv $OUTPUT_DIR/result/result.tsv

    for file in $INPUT_DIR/*.fasta ; do 
        filename=\$(basename \$file .fasta)

        kaptive assembly /database/Acinetobacter_baumannii_k_locus_primary_reference.gbk_K.gbk \$file -o $OUTPUT_DIR/tempdir/\${filename}_k.tsv
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}_k.tsv >> $OUTPUT_DIR/result/result.tsv

        kaptive assembly /database/Acinetobacter_baumannii_k_locus_primary_reference.gbk_OC.gbk \$file -o $OUTPUT_DIR/tempdir/\${filename}_o.tsv
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}_o.tsv >> $OUTPUT_DIR/result/result.tsv

    done
    "

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 鲍曼不动杆菌血清型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 鲍曼不动杆菌血清型分析失败"
    fi

# 5. 副溶血弧菌血清型分析
elif [ "$SPECIES" = "vp" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 副溶血弧菌血清型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR kaptive:v3.1.0 \
    bash -c " cp /head.tsv $OUTPUT_DIR/result/result.tsv

    for file in $INPUT_DIR/*.fasta ; do 
        filename=\$(basename \$file .fasta)

        kaptive assembly /database/VibrioPara_Kaptivedb_K.gbk \$file -o $OUTPUT_DIR/tempdir/\${filename}_k.tsv
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}_k.tsv >> $OUTPUT_DIR/result/result.tsv

        kaptive assembly /database/VibrioPara_Kaptivedb_O.gbk \$file -o $OUTPUT_DIR/tempdir/\${filename}_o.tsv
        sed -n '2p' $OUTPUT_DIR/tempdir/\${filename}_o.tsv >> $OUTPUT_DIR/result/result.tsv

    done
    "

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 副溶血弧菌血清型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 副溶血弧菌血清型分析失败"
    fi

# 6. A族链球菌emm分型分析
elif [ "$SPECIES" = "gas" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') A族链球菌emm分型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR emmtyper:v1.0 \
    /bin/bash -c "cd $OUTPUT_DIR/tempdir && emmtyper $INPUT_DIR/* --percent-identity 99 -f short -k -o $OUTPUT_DIR/tempdir/result.txt 2>> $OUTPUT_DIR/logdir/emmtyper.log"

    cp $OUTPUT_DIR/tempdir/result.txt $OUTPUT_DIR/result/result.tsv

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') A族链球菌emm分型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') A族链球菌emm分型分析失败"
    fi

# 7. 肺炎链球菌分型分析
elif [ "$SPECIES" = "sp" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 肺炎链球菌分型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR pneumo_type:v2.0.1 \
    pneumo-typer -d $INPUT_DIR/ -m T -c T -t 24 -o $OUTPUT_DIR/tempdir >> $OUTPUT_DIR/logdir/pneumo_type.log 2>&1

    cp $OUTPUT_DIR/tempdir/Serotype_CapT_ST.out $OUTPUT_DIR/result/result.tsv

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 肺炎链球菌分型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 肺炎链球菌分型分析失败"
    fi

# 8. 猪链球菌血清分型分析
elif [ "$SPECIES" = "ss" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 猪链球菌血清分型分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR ssuis:v1.0 \
    bash -c "cd /SsuisChara && python SsuisChara.py -i $INPUT_DIR/*.fasta -o $OUTPUT_DIR/tempdir/result.tsv -t 24 >> $OUTPUT_DIR/logdir/SsuisChara.log 2>&1"

    cp $OUTPUT_DIR/tempdir/result.tsv $OUTPUT_DIR/result/result.tsv

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 猪链球菌血清分型分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 猪链球菌血清分型分析失败"
    fi

# 9. 脑膜炎耐瑟菌血清群分析
elif [ "$SPECIES" = "nm" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 脑膜炎耐瑟菌血清群分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR meningotype:v0.8.5 \
    sh -c "cd $INPUT_DIR && meningotype --finetype --porB --bast --cpus 24 --printseq $OUTPUT_DIR/tempdir/fasta *.fasta > $OUTPUT_DIR/tempdir/result.tsv 2> /dev/null"

    cp $OUTPUT_DIR/tempdir/result.tsv $OUTPUT_DIR/result/result.tsv

    if [ -f "$OUTPUT_DIR/result/result.tsv" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 脑膜炎耐瑟菌血清群分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 脑膜炎耐瑟菌血清群分析失败"
    fi

# 10. 霍乱弧菌血清群分析
elif [ "$SPECIES" = "vc" ]; then
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 霍乱弧菌血清群分析开始"

    docker run --rm -v $INPUT_DIR:$INPUT_DIR -v $OUTPUT_DIR:$OUTPUT_DIR choleraefinder:v1.0 \
    bash -c "

    for file in $INPUT_DIR/*.fasta ; do 
        filename=\$(basename \$file .fasta)

        mkdir $OUTPUT_DIR/tempdir/\${filename}
        choleraefinder.py -i \$file -o $OUTPUT_DIR/tempdir/\${filename}  -mp blastn -p /choleraefinder_db -matrix -q -x

        cp $OUTPUT_DIR/tempdir/\${filename}/results_tab.tsv $OUTPUT_DIR/result/\${filename}.tsv

    done
    "

    if [ -n "$(find $OUTPUT_DIR/result -maxdepth 1 -name '*.tsv' -print -quit)" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 霍乱弧菌血清群分析完成"
    else
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') 霍乱弧菌血清群分析失败"
    fi

else

echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') 物种名输入错误, 请重试"

fi