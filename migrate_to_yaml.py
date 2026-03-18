"""Auto-migrates kalshi_bot.py: comments old hardcodes + injects CONFIG override"""
import yaml
import shutil

shutil.copy("kalshi_bot.py", "kalshi_bot.py.bak")
print("Backup created: kalshi_bot.py.bak")

with open("config.yaml") as f:
    cfg = yaml.safe_load(f)

with open("kalshi_bot.py") as f:
    lines = f.readlines()

new_lines = []
added = False
for line in lines:
    stripped = line.strip()
    if (stripped.startswith("DRY_RUN =") or 
        (stripped and stripped[0].isupper() and "=" in stripped and not stripped.startswith("#"))):
        new_lines.append("# " + line)  # comment old hardcoded
        continue
    new_lines.append(line)
    if "from timing import" in line and not added:
        new_lines.append("\n")
        new_lines.append("from config_loader import load_config\n")
        new_lines.append("CONFIG = load_config()\n")
        # Override globals so DRY_RUN still works everywhere
        new_lines.append("for k, v in vars(CONFIG).items():\n")
        new_lines.append("    if k.isupper():\n")
        new_lines.append("        globals()[k] = v\n")
        added = True

with open("kalshi_bot.py", "w") as f:
    f.writelines(new_lines)

print("✅ kalshi_bot.py migrated! Hardcodes commented, CONFIG now controls everything.")
print("Test with: python kalshi_bot.py --status")
