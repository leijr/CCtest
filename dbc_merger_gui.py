"""
DBC 文件合并工具 - GUI 上位机
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
import threading
import os
from pathlib import Path
from dbc_merger import DBCMerger, MergeResult


class DBCMergerGUI:
    """DBC 合并工具 GUI"""

    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("DBC 文件合并工具")
        self.root.geometry("800x600")
        self.root.minsize(600, 400)

        self.merger = DBCMerger()
        self.file_list: list[str] = []

        self._create_widgets()

    def _create_widgets(self):
        """创建界面组件"""
        # 主框架
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # 文件列表区域
        file_frame = ttk.LabelFrame(main_frame, text="DBC 文件列表", padding="10")
        file_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        # 列表和滚动条
        list_frame = ttk.Frame(file_frame)
        list_frame.pack(fill=tk.BOTH, expand=True)

        self.file_listbox = tk.Listbox(list_frame, selectmode=tk.EXTENDED, height=8)
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.file_listbox.yview)
        self.file_listbox.configure(yscrollcommand=scrollbar.set)

        self.file_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # 文件操作按钮
        btn_frame = ttk.Frame(file_frame)
        btn_frame.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(btn_frame, text="添加文件", command=self._add_files).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="添加文件夹", command=self._add_folder).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="移除选中", command=self._remove_selected).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="清空列表", command=self._clear_list).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="上移", command=self._move_up).pack(side=tk.RIGHT, padx=5)
        ttk.Button(btn_frame, text="下移", command=self._move_down).pack(side=tk.RIGHT, padx=5)

        # 输出设置区域
        output_frame = ttk.LabelFrame(main_frame, text="输出设置", padding="10")
        output_frame.pack(fill=tk.X, pady=(0, 10))

        output_inner = ttk.Frame(output_frame)
        output_inner.pack(fill=tk.X)

        ttk.Label(output_inner, text="输出文件:").pack(side=tk.LEFT)
        self.output_path = tk.StringVar()
        ttk.Entry(output_inner, textvariable=self.output_path, width=50).pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
        ttk.Button(output_inner, text="浏览", command=self._browse_output).pack(side=tk.LEFT)

        # 日志区域
        log_frame = ttk.LabelFrame(main_frame, text="日志信息", padding="10")
        log_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        self.log_text = scrolledtext.ScrolledText(log_frame, height=10, state=tk.DISABLED)
        self.log_text.pack(fill=tk.BOTH, expand=True)

        # 底部按钮区域
        bottom_frame = ttk.Frame(main_frame)
        bottom_frame.pack(fill=tk.X)

        ttk.Button(bottom_frame, text="合并预览", command=self._preview_merge).pack(side=tk.LEFT, padx=5)
        ttk.Button(bottom_frame, text="执行合并", command=self._execute_merge, style='Accent.TButton').pack(side=tk.LEFT, padx=5)
        ttk.Button(bottom_frame, text="退出", command=self.root.quit).pack(side=tk.RIGHT, padx=5)

        # 进度条
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Progressbar(bottom_frame, variable=self.progress_var, maximum=100)
        self.progress_bar.pack(side=tk.RIGHT, fill=tk.X, expand=True, padx=10)

    def _log(self, message: str, level: str = "INFO"):
        """添加日志"""
        self.log_text.configure(state=tk.NORMAL)
        prefix = f"[{level}] "
        self.log_text.insert(tk.END, prefix + message + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def _add_files(self):
        """添加文件"""
        files = filedialog.askopenfilenames(
            title="选择 DBC 文件",
            filetypes=[("DBC 文件", "*.dbc"), ("所有文件", "*.*")]
        )
        for file in files:
            if file not in self.file_list:
                self.file_list.append(file)
                self.file_listbox.insert(tk.END, os.path.basename(file))
        self._log(f"添加了 {len(files)} 个文件")

    def _add_folder(self):
        """添加文件夹中的 DBC 文件"""
        folder = filedialog.askdirectory(title="选择文件夹")
        if folder:
            dbc_files = list(Path(folder).glob("*.dbc"))
            count = 0
            for dbc_file in dbc_files:
                file_path = str(dbc_file)
                if file_path not in self.file_list:
                    self.file_list.append(file_path)
                    self.file_listbox.insert(tk.END, dbc_file.name)
                    count += 1
            self._log(f"从文件夹添加了 {count} 个 DBC 文件")

    def _remove_selected(self):
        """移除选中的文件"""
        selection = self.file_listbox.curselection()
        for index in reversed(selection):
            self.file_list.pop(index)
            self.file_listbox.delete(index)
        self._log(f"移除了 {len(selection)} 个文件")

    def _clear_list(self):
        """清空列表"""
        self.file_list.clear()
        self.file_listbox.delete(0, tk.END)
        self._log("已清空文件列表")

    def _move_up(self):
        """上移选中项"""
        selection = self.file_listbox.curselection()
        if not selection:
            return
        for index in selection:
            if index > 0:
                self.file_list[index], self.file_list[index-1] = self.file_list[index-1], self.file_list[index]
                item = self.file_listbox.get(index)
                self.file_listbox.delete(index)
                self.file_listbox.insert(index-1, item)
                self.file_listbox.selection_set(index-1)

    def _move_down(self):
        """下移选中项"""
        selection = self.file_listbox.curselection()
        if not selection:
            return
        for index in reversed(selection):
            if index < self.file_listbox.size() - 1:
                self.file_list[index], self.file_list[index+1] = self.file_list[index+1], self.file_list[index]
                item = self.file_listbox.get(index)
                self.file_listbox.delete(index)
                self.file_listbox.insert(index+1, item)
                self.file_listbox.selection_set(index+1)

    def _browse_output(self):
        """选择输出文件"""
        file_path = filedialog.asksaveasfilename(
            title="保存合并后的 DBC 文件",
            defaultextension=".dbc",
            filetypes=[("DBC 文件", "*.dbc"), ("所有文件", "*.*")]
        )
        if file_path:
            self.output_path.set(file_path)

    def _validate_inputs(self) -> bool:
        """验证输入"""
        if len(self.file_list) < 2:
            messagebox.showwarning("警告", "请至少添加 2 个 DBC 文件进行合并")
            return False

        if not self.output_path.get():
            messagebox.showwarning("警告", "请指定输出文件路径")
            return False

        return True

    def _preview_merge(self):
        """预览合并"""
        if not self._validate_inputs():
            return

        self._log("开始预览合并...")
        self.progress_bar['value'] = 0

        def do_preview():
            try:
                result = self.merger.merge_dbc_files(self.file_list)
                self.root.after(0, lambda: self._on_preview_complete(result))
            except Exception as e:
                self.root.after(0, lambda: self._log(f"预览失败: {e}", "ERROR"))

        thread = threading.Thread(target=do_preview)
        thread.start()

    def _on_preview_complete(self, result: MergeResult):
        """预览完成回调"""
        self.progress_bar['value'] = 100

        if result.success:
            self._log(result.message)
            self._log(f"统计信息: {result.stats}")
            self._log(self.merger.get_merge_summary())
        else:
            self._log(result.message, "ERROR")

    def _execute_merge(self):
        """执行合并"""
        if not self._validate_inputs():
            return

        output = self.output_path.get()

        self._log("开始执行合并...")
        self.progress_bar['value'] = 0

        def do_merge():
            try:
                result = self.merger.merge_dbc_files(self.file_list)

                if result.success:
                    if self.merger.save_merged_dbc(output):
                        self.root.after(0, lambda: self._on_merge_success(result, output))
                    else:
                        self.root.after(0, lambda: self._log("保存文件失败", "ERROR"))
                else:
                    self.root.after(0, lambda: self._log(result.message, "ERROR"))

            except Exception as e:
                self.root.after(0, lambda: self._log(f"合并失败: {e}", "ERROR"))

        thread = threading.Thread(target=do_merge)
        thread.start()

    def _on_merge_success(self, result: MergeResult, output_path: str):
        """合并成功回调"""
        self.progress_bar['value'] = 100
        self._log(result.message)
        self._log(f"统计信息: {result.stats}")
        self._log(f"已保存到: {output_path}")
        self._log(self.merger.get_merge_summary())

        messagebox.showinfo("成功", f"DBC 文件合并完成！\n已保存到: {output_path}")


def main():
    root = tk.Tk()

    # 设置样式
    style = ttk.Style()
    try:
        style.configure('Accent.TButton', font=('Helvetica', 10, 'bold'))
    except:
        pass

    app = DBCMergerGUI(root)
    root.mainloop()


if __name__ == '__main__':
    main()