#!/bin/bash
# 端口转发脚本：将宿主机端口映射到鸿蒙模拟器端口
# 用于 FTP 被动模式数据连接

DEVICE="127.0.0.1:5555"

# 控制端口
hdc -t $DEVICE fport tcp:2121 tcp:2121

# 被动模式数据端口范围 50000-50100
for port in {50000..50100}; do
  hdc -t $DEVICE fport tcp:$port tcp:$port
done

echo "✓ 端口转发完成："
echo "  - 控制端口: 2121"
echo "  - 数据端口: 50000-50100"
