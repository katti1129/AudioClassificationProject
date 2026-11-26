"""Operator GUI; keep this window focused to receive participant WASD input."""
import argparse
import queue
import re
import threading
import time
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import sounddevice as sd
from common import ROOT, KEYS, config, load_trials
from controller import Controller


class App:
    def __init__(self, root, cfg):
        self.root, self.cfg = root, cfg
        self.messages = queue.Queue()
        self.controller = None
        self.running = False
        self.held = set()
        root.title("音声支援実験 — 実験者用")
        root.geometry("980x680")
        self.participant = tk.StringVar(value="P001")
        self.condition = tk.StringVar(value="support_on")
        self.mode = tk.StringVar(value="practice")
        self.list_path = tk.StringVar(value=str(ROOT / "trials.csv"))
        self.status = tk.StringVar(value="機器・左右・マイク感度を事前確認してください")
        self.detail = tk.StringVar()
        self.meter = tk.StringVar()
        self.path_label = tk.StringVar()
        form = ttk.Frame(root, padding=15)
        form.pack(fill="x")
        self.editors = []
        for r, (label, var, values) in enumerate([
            ("参加者ID", self.participant, None),
            ("条件（ARアプリの切替は手動）", self.condition, ["support_on", "support_off"]),
            ("モード", self.mode, ["practice", "main"])]):
            ttk.Label(form, text=label).grid(row=r, column=0, sticky="w", pady=4)
            widget = ttk.Combobox(form, textvariable=var, values=values, state="readonly") if values else ttk.Entry(form, textvariable=var)
            widget.grid(row=r, column=1, sticky="w")
            self.editors.append(widget)
        ttk.Label(form, text="再生リスト").grid(row=3, column=0, sticky="w")
        self.list_entry = ttk.Entry(form, textvariable=self.list_path, width=65)
        self.list_entry.grid(row=3, column=1)
        self.editors.append(self.list_entry)
        self.browse = ttk.Button(form, text="選択", command=self.choose)
        self.browse.grid(row=3, column=2)
        self.device_names = {}
        for i, d in enumerate(sd.query_devices()):
            self.device_names[f"{i}: {d['name']} ({sd.query_hostapis(d['hostapi'])['name']})"] = i
        self.input_choice = tk.StringVar()
        self.output_choice = tk.StringVar()
        for r, label, variable, field, kind in [(4, "入力：NSW-088を選択", self.input_choice, "input_device", "input"),
                                                (5, "出力：親PCスピーカー", self.output_choice, "output_device", "output")]:
            values = [n for n, i in self.device_names.items() if sd.query_devices(i)[f"max_{kind}_channels"] >= (1 if kind == "input" else 2)]
            ttk.Label(form, text=label).grid(row=r, column=0, sticky="w")
            cb = ttk.Combobox(form, textvariable=variable, values=values, width=65, state="readonly")
            cb.grid(row=r, column=1, pady=4)
            self.editors.append(cb)
            for n in values:
                if self.device_names[n] == cfg[field]:
                    variable.set(n)
        ttk.Label(root, text="W=北 / D=東 / S=南 / A=西。サイレンと判断した場合のみ回答。",
                  font=("Yu Gothic", 12)).pack(pady=8)
        ttk.Label(root, text="時刻は未校正なら暫定値です。AR表示は変更しません。", foreground="#a06000").pack()
        ttk.Label(root, textvariable=self.status, font=("Yu Gothic", 18)).pack(pady=12)
        ttk.Label(root, textvariable=self.detail).pack()
        ttk.Label(root, textvariable=self.meter).pack()
        controls = ttk.Frame(root, padding=12)
        controls.pack()
        self.start_button = ttk.Button(controls, text="開始", command=self.start)
        self.start_button.pack(side="left", padx=5)
        ttk.Button(controls, text="この試行後に一時停止", command=self.pause).pack(side="left", padx=5)
        ttk.Button(controls, text="再開 / 次の練習", command=self.resume).pack(side="left", padx=5)
        ttk.Button(controls, text="緊急停止", command=self.stop).pack(side="left", padx=5)
        columns = ("trial", "direction", "response", "outcome", "rt")
        self.table = ttk.Treeview(root, columns=columns, show="headings", height=7)
        for col, title in zip(columns, ["試行", "正解方向", "回答", "結果", "回答時間（暫定・秒）"]):
            self.table.heading(col, text=title)
            self.table.column(col, width=175)
        self.table.pack(fill="both", expand=True, padx=15)
        ttk.Label(root, textvariable=self.path_label).pack(pady=8)
        root.bind_all("<KeyPress>", self.key_down)
        root.bind_all("<KeyRelease>", lambda e: self.held.discard(e.keysym.lower()))
        root.bind("<FocusOut>", self.focus_out)
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.after(50, self.poll)

    def choose(self):
        name = filedialog.askopenfilename(filetypes=[("CSV", "*.csv")])
        if name:
            self.list_path.set(name)

    def start(self):
        try:
            if self.running:
                return
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", self.participant.get()):
                raise ValueError("参加者IDは英数字・ハイフン・アンダースコアで指定してください")
            cfg = dict(self.cfg)
            cfg["input_device"] = self.device_names[self.input_choice.get()]
            cfg["output_device"] = self.device_names[self.output_choice.get()]
            sd.check_input_settings(device=cfg["input_device"], channels=1, samplerate=cfg["sample_rate"])
            sd.check_output_settings(device=cfg["output_device"], channels=2, samplerate=cfg["sample_rate"])
            rows = load_trials(self.list_path.get())
            self.controller = Controller(cfg, rows, self.participant.get(), self.condition.get(), self.mode.get(), self.messages)
            self.running = True
            for w in self.editors + [self.browse, self.start_button]:
                w.configure(state="disabled")
            self.root.focus_set()
            threading.Thread(target=self.controller.run, daemon=True).start()
        except Exception as e:
            messagebox.showerror("開始できません", str(e))

    def key_down(self, event):
        key = event.keysym.lower()
        if self.running and key in KEYS and key not in self.held:
            self.controller.key(KEYS[key], time.perf_counter())
        self.held.add(key)

    def focus_out(self, event):
        # Changing widgets within this app is allowed; leaving the app invalidates input capture.
        if self.running:
            self.root.after(50, self.check_focus)

    def check_focus(self):
        if self.running and self.root.focus_displayof() is None:
            self.stop()

    def pause(self):
        if self.running:
            self.controller.pause_event.set()

    def resume(self):
        if self.running:
            self.controller.pause_event.clear()
            self.root.focus_set()

    def stop(self):
        if self.running:
            self.controller.stop_event.set()
            self.status.set("停止要求中（子PC通信タイムアウトは最大約2秒）")

    def close(self):
        if self.running:
            self.stop()
            self.root.after(100, self.close)
        else:
            self.root.destroy()

    def poll(self):
        while not self.messages.empty():
            msg = self.messages.get_nowait()
            self.status.set(msg["state"])
            if "trial" in msg:
                r = msg["trial"]
                self.detail.set(f"{msg['number']} / {msg['total']}   {r['direction']} / {r['class']} / {r['file']}")
            if "peak" in msg:
                elapsed = msg["elapsed"]
                self.meter.set(f"マイクピーク {msg['peak']:.1f} dBFS  |  発音後 {elapsed:.2f}秒" if elapsed is not None else f"マイクピーク {msg['peak']:.1f} dBFS")
            if "row" in msg:
                r = msg["row"]
                self.table.insert("", "end", values=(r["trial_id"], r["direction"], r["response"], r["outcome"],
                                                       f"{r['rt_s']:.4f}" if r["rt_s"] != "" else ""))
            if "folder" in msg:
                self.path_label.set(msg["folder"])
            if "error" in msg:
                self.detail.set(msg["error"])
            if msg["state"] == "終了処理完了":
                self.running = False
                self.status.set("停止済み / 完了 — 詳細と保存結果を確認してください")
                for w in self.editors:
                    w.configure(state="readonly" if isinstance(w, ttk.Combobox) else "normal")
                self.browse.configure(state="normal")
                self.start_button.configure(state="normal")
        self.root.after(50, self.poll)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--config", default="config.local.json")
    p.add_argument("--list-devices", action="store_true")
    args = p.parse_args()
    if args.list_devices:
        print(sd.query_devices())
    else:
        root = tk.Tk()
        App(root, config(args.config))
        root.mainloop()
