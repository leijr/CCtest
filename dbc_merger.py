"""
DBC 文件合并工具
支持合并多个 DBC 文件，处理重复 ID 和属性
"""

import cantools
from typing import Dict, List, Set, Any
from dataclasses import dataclass, field
import os


@dataclass
class MergeResult:
    """合并结果"""
    success: bool
    message: str
    stats: Dict[str, int] = field(default_factory=dict)


class DBCMerger:
    """DBC 文件合并器"""

    def __init__(self):
        self.merged_db = None
        self.message_ids: Dict[int, str] = {}  # ID -> 消息名映射
        self.signal_names: Dict[str, Set[int]] = {}  # 信号名 -> 消息ID集合
        self.conflicts: List[str] = []

    def load_dbc(self, file_path: str) -> cantools.database.Database:
        """加载 DBC 文件"""
        try:
            return cantools.database.load_file(file_path)
        except Exception as e:
            raise ValueError(f"加载 DBC 文件失败: {file_path}\n错误: {e}")

    def merge_messages(self, target_db: cantools.database.Database,
                       source_db: cantools.database.Database,
                       source_name: str) -> Dict[str, int]:
        """
        合并消息
        返回统计信息
        """
        stats = {
            'messages_added': 0,
            'messages_merged': 0,
            'signals_added': 0,
            'signals_merged': 0,
            'conflicts': 0
        }

        for msg in source_db.messages:
            existing_msg = None

            # 查找相同 ID 的消息
            for target_msg in target_db.messages:
                if target_msg.frame_id == msg.frame_id:
                    existing_msg = target_msg
                    break

            if existing_msg is None:
                # 新消息，直接添加
                target_db.messages.append(msg)
                self.message_ids[msg.frame_id] = msg.name
                stats['messages_added'] += 1

                # 添加信号
                for sig in msg.signals:
                    if sig.name not in self.signal_names:
                        self.signal_names[sig.name] = set()
                    self.signal_names[sig.name].add(msg.frame_id)
                    stats['signals_added'] += 1
            else:
                # 存在相同 ID 的消息，合并信号
                stats['messages_merged'] += 1

                for sig in msg.signals:
                    signal_exists = False
                    for existing_sig in existing_msg.signals:
                        if existing_sig.name == sig.name:
                            signal_exists = True
                            # 检查信号属性是否一致
                            if not self._compare_signals(existing_sig, sig):
                                conflict_msg = f"信号冲突: {msg.name}::{sig.name} 属性不一致"
                                self.conflicts.append(f"[{source_name}] {conflict_msg}")
                                stats['conflicts'] += 1
                            break

                    if not signal_exists:
                        # 新信号，添加到现有消息
                        existing_msg.signals.append(sig)
                        if sig.name not in self.signal_names:
                            self.signal_names[sig.name] = set()
                        self.signal_names[sig.name].add(msg.frame_id)
                        stats['signals_added'] += 1

        return stats

    def _compare_signals(self, sig1: cantools.database.Signal,
                         sig2: cantools.database.Signal) -> bool:
        """比较两个信号的主要属性是否一致"""
        attrs = ['start', 'length', 'byte_order', 'scale',
                 'offset', 'minimum', 'maximum', 'unit']

        for attr in attrs:
            if getattr(sig1, attr, None) != getattr(sig2, attr, None):
                return False
        return True

    def merge_nodes(self, target_db: cantools.database.Database,
                    source_db: cantools.database.Database) -> int:
        """合并节点"""
        added = 0
        existing_names = {node.name for node in target_db.nodes}

        for node in source_db.nodes:
            if node.name not in existing_names:
                target_db.nodes.append(node)
                added += 1

        return added

    def merge_dbc_files(self, file_paths: List[str],
                        handle_conflicts: str = 'keep_first') -> MergeResult:
        """
        合并多个 DBC 文件

        Args:
            file_paths: DBC 文件路径列表
            handle_conflicts: 冲突处理方式
                - 'keep_first': 保留第一个文件的属性
                - 'keep_last': 使用最后一个文件的属性
                - 'rename': 重命名冲突项

        Returns:
            MergeResult: 合并结果
        """
        if not file_paths:
            return MergeResult(False, "没有提供 DBC 文件")

        self.conflicts = []
        total_stats = {
            'messages_added': 0,
            'messages_merged': 0,
            'signals_added': 0,
            'signals_merged': 0,
            'nodes_added': 0,
            'conflicts': 0
        }

        try:
            # 加载第一个文件作为基础
            self.merged_db = self.load_dbc(file_paths[0])

            for msg in self.merged_db.messages:
                self.message_ids[msg.frame_id] = msg.name
                for sig in msg.signals:
                    if sig.name not in self.signal_names:
                        self.signal_names[sig.name] = set()
                    self.signal_names[sig.name].add(msg.frame_id)

            # 合并其他文件
            for file_path in file_paths[1:]:
                source_db = self.load_dbc(file_path)
                source_name = os.path.basename(file_path)

                # 合并消息
                msg_stats = self.merge_messages(self.merged_db, source_db, source_name)
                for key in ['messages_added', 'messages_merged', 'signals_added', 'conflicts']:
                    total_stats[key] += msg_stats[key]

                # 合并节点
                nodes_added = self.merge_nodes(self.merged_db, source_db)
                total_stats['nodes_added'] += nodes_added

            total_stats['conflicts'] = len(self.conflicts)

            return MergeResult(
                success=True,
                message=f"成功合并 {len(file_paths)} 个 DBC 文件",
                stats=total_stats
            )

        except Exception as e:
            return MergeResult(False, f"合并失败: {str(e)}")

    def save_merged_dbc(self, output_path: str) -> bool:
        """保存合并后的 DBC 文件"""
        if self.merged_db is None:
            return False

        try:
            # cantools 的 as_dbc_string 方法
            dbc_string = self.merged_db.as_dbc_string()
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(dbc_string)
            return True
        except Exception as e:
            print(f"保存失败: {e}")
            return False

    def get_merge_summary(self) -> str:
        """获取合并摘要信息"""
        if self.merged_db is None:
            return "尚未进行合并"

        summary = [
            f"合并结果摘要:",
            f"  消息总数: {len(self.merged_db.messages)}",
            f"  节点总数: {len(self.merged_db.nodes)}",
            f"  信号总数: {sum(len(msg.signals) for msg in self.merged_db.messages)}",
        ]

        if self.conflicts:
            summary.append(f"\n冲突信息 ({len(self.conflicts)} 项):")
            for conflict in self.conflicts[:10]:  # 只显示前10条
                summary.append(f"  - {conflict}")
            if len(self.conflicts) > 10:
                summary.append(f"  ... 还有 {len(self.conflicts) - 10} 条冲突")

        return "\n".join(summary)


def main():
    """命令行入口"""
    import argparse

    parser = argparse.ArgumentParser(description='DBC 文件合并工具')
    parser.add_argument('inputs', nargs='+', help='输入 DBC 文件路径')
    parser.add_argument('-o', '--output', required=True, help='输出 DBC 文件路径')

    args = parser.parse_args()

    merger = DBCMerger()
    result = merger.merge_dbc_files(args.inputs)

    if result.success:
        print(result.message)
        print(f"统计: {result.stats}")
        merger.save_merged_dbc(args.output)
        print(f"已保存到: {args.output}")
        print(merger.get_merge_summary())
    else:
        print(f"错误: {result.message}")


if __name__ == '__main__':
    main()