#!/usr/bin/env python3
import re
import sys
import zipfile
from pathlib import Path

apk = Path(sys.argv[1])
out = Path(sys.argv[2])
report = Path(sys.argv[3])
report.mkdir(parents=True, exist_ok=True)

sources = out / 'sources'
java_files = sorted(sources.rglob('*.java')) if sources.exists() else []

with zipfile.ZipFile(apk) as z:
    dex = [(n, z.getinfo(n).file_size) for n in z.namelist() if re.fullmatch(r'classes\d*\.dex', Path(n).name)]
    native = [(n, z.getinfo(n).file_size) for n in z.namelist() if n.endswith('.so')]
    special = [(n, z.getinfo(n).file_size) for n in z.namelist() if n in ('assets/signed.bin','assets/af.bin') or 'ranger' in n.lower()]

patterns = {
    'native_methods': re.compile(r'\bnative\b'),
    'load_library': re.compile(r'System\.loadLibrary|System\.load\('),
    'dex_loader': re.compile(r'DexClassLoader|PathClassLoader|BaseDexClassLoader|loadClass\('),
    'reflection': re.compile(r'Class\.forName|getDeclaredMethod|getDeclaredField|Method\.invoke'),
    'application': re.compile(r'extends\s+Application|\bonCreate\s*\('),
    'ui_layout': re.compile(r'setContentView\s*\(|inflate\s*\(|R\.layout\.'),
    'orientation': re.compile(r'setRequestedOrientation|SCREEN_ORIENTATION|screenOrientation'),
    'window_metrics': re.compile(r'DisplayMetrics|WindowManager|getDefaultDisplay|getRealMetrics'),
}

hits = {k: [] for k in patterns}
class_lines = []
for f in java_files:
    rel = f.relative_to(sources)
    text = f.read_text(encoding='utf-8', errors='ignore')
    m = re.search(r'(?m)^\s*(?:public\s+)?(?:final\s+)?class\s+([A-Za-z0-9_$]+)|^\s*(?:public\s+)?interface\s+([A-Za-z0-9_$]+)', text)
    class_name = next((g for g in (m.groups() if m else ()) if g), f.stem)
    class_lines.append(f'{rel}  ({len(text)} chars)')
    for key, pat in patterns.items():
        if pat.search(text):
            snippets=[]
            for i,line in enumerate(text.splitlines(),1):
                if pat.search(line):
                    snippets.append(f'{rel}:{i}: {line.strip()[:220]}')
                    if len(snippets) >= 8: break
            hits[key].extend(snippets)

(report/'classes.txt').write_text('\n'.join(class_lines), encoding='utf-8')
for key, lines in hits.items():
    (report/f'{key}.txt').write_text('\n'.join(lines), encoding='utf-8')

# Keep small source excerpts for rapid review, without exporting resources or network data.
excerpts=[]
for f in java_files:
    text=f.read_text(encoding='utf-8',errors='ignore')
    excerpts.append(f'===== {f.relative_to(sources)} =====\n{text[:12000]}\n')
(report/'source-excerpts.txt').write_text('\n'.join(excerpts),encoding='utf-8')

summary=[]
summary.append(f'APK: {apk.name}')
summary.append(f'DEX files: {len(dex)}')
for n,s in dex: summary.append(f'  {n}: {s} bytes')
summary.append(f'Native libraries: {len(native)} files, {sum(s for _,s in native)} bytes total')
summary.append('Special packed/protection-looking files:')
for n,s in special: summary.append(f'  {n}: {s} bytes')
summary.append(f'JADX Java files recovered: {len(java_files)}')
summary.append('')
summary.append('Recovered classes:')
for line in class_lines[:100]: summary.append('  '+line)
summary.append('')
for key in patterns:
    summary.append(f'{key}: {len(hits[key])} matching lines')
    for line in hits[key][:12]: summary.append('  '+line)
    summary.append('')

# A conservative usefulness signal for UI adaptation.
ui_signal = bool(hits['ui_layout'] or hits['orientation'] or hits['window_metrics'])
loader_signal = bool(hits['load_library'] or hits['dex_loader'] or hits['reflection'] or hits['native_methods'])
summary.append('Assessment:')
if ui_signal:
    summary.append('  JADX recovered at least some directly editable-looking UI/orientation code. Review manually before any experiment.')
elif loader_signal:
    summary.append('  Recovered DEX is dominated by loader/native/reflection behavior and exposes no direct UI adaptation code.')
else:
    summary.append('  Recovered DEX exposes little or no obvious UI code; likely not useful for direct mobile redesign.')

(report/'summary.txt').write_text('\n'.join(summary)+'\n', encoding='utf-8')
