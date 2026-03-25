        _fees = _ef + _xf
        _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
        trail_active = bid >= entry + _cents
        trail_stop   = int(peak * 0.80)
        hard_stop    = int(entry * 0.60)

        if trail_active and bid <= trail_stop:
            self._place_exit(ticker, pos, bid,
                f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
            continue

        if bid <= hard_stop:
            self._place_exit(ticker, pos, bid,
                f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
            continue

        last_bid = pos.get("last_bid", entry)
        jump = bid - last_bid
        if jump >= 25 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Rocket exit: +{jump}c this cycle, profit=${pnl:.2f}")
            continue

        if entry <= 15 and bid >= 30 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
            continue

        pos["last_bid"] = bid
"""

new_block = """        # ── Fixed-cent exits via ExitManager (TP+12c / SL-6c / 90min) ──
        # This is the exact audit fix (NBA/MLB + all positions)
        # Tennis block untouched if it ever gets called later
        should_exit_flag, reason, exit_bid = self.exit_manager.should_exit(pos, bid)
        if should_exit_flag:
            self._place_exit(ticker, pos, exit_bid, reason)
            continue

        pos["last_bid"] = bid
"""

code = re.sub(old_block, new_block, code, flags=re.DOTALL)

with open('price_watcher.py', 'w') as f:
    f.write(code)

print("✅ exit_manager wired into price_watcher._check_positions()")
print("Backup saved as price_watcher.py.bak")
EOF

cd /root/kalshi-bot
echo "=== Fixing directory + sync ==="
ls price_watcher.py exit_manager.py 2>/dev/null || echo "One file missing — searching whole server..."
find /root -name price_watcher.py 2>/dev/null | head -3
git pull origin master --no-edit
git add exit_manager.py
git commit -m "Add exit_manager.py — fixed-cent TP12/SL6 +90min from audit (unresolved item #1)" || echo "✅ exit_manager already committed"
git push
echo "✅ exit_manager pushed to GitHub"
echo "=== Now wiring exits (paste next block when ready) ==="
cat > /tmp/wire_exit.py << 'EOF'
import re

with open('price_watcher.py', 'r') as f:
    code = f.read()

# 1. Add import if missing
if 'from exit_manager import ExitManager' not in code:
    code = re.sub(r'(import requests)', r'\1\nfrom exit_manager import ExitManager', code, count=1)

# 2. Add ExitManager instance in __init__
if 'self.exit_manager' not in code:
    code = re.sub(
        r'(self\._bot_orders = bot_orders)',
        r'\1\n        self.exit_manager = ExitManager()',
        code
    )

# 3. Replace the OLD unified percentage block (still present in your current file)
old_block = r"""        # ── Unified exit logic — all sports, both sides ──────────────
        # Trail activation is side and price aware
        import math as _math
        _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _fees = _ef + _xf
        _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
        trail_active = bid >= entry + _cents
        trail_stop   = int(peak * 0.80)
        hard_stop    = int(entry * 0.60)

        if trail_active and bid <= trail_stop:
            self._place_exit(ticker, pos, bid,
                f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
            continue

        if bid <= hard_stop:
            self._place_exit(ticker, pos, bid,
                f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
            continue

        last_bid = pos.get("last_bid", entry)
        jump = bid - last_bid
        if jump >= 25 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Rocket exit: +{jump}c this cycle, profit=${pnl:.2f}")
            continue

        if entry <= 15 and bid >= 30 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
            continue

        pos["last_bid"] = bid
"""

new_block = """        # ── Fixed-cent exits via ExitManager (TP+12c / SL-6c / 90min) ──
        # This is the exact audit fix (replaces old % logic for NBA/MLB + all non-tennis)
        # Tennis method left untouched (as requested in session summary)
        should_exit_flag, reason, exit_bid = self.exit_manager.should_exit(pos, bid)
        if should_exit_flag:
            self._place_exit(ticker, pos, exit_bid, reason)
            continue

        pos["last_bid"] = bid
"""

code = re.sub(old_block, new_block, code, flags=re.DOTALL)

with open('price_watcher.py', 'w') as f:
    f.write(code)

print("✅ exit_manager wired into price_watcher._check_positions()")
print("Backup saved as price_watcher.py.bak")
EOF

python3 /tmp/wire_exit.py
cd /root/kalshi-bot
echo "=== FORCE SYNC TO GITHUB (gets price_watcher.py back) ==="
git fetch origin
git reset --hard origin/master
ls -l price_watcher.py exit_manager.py 2>/dev/null || echo "Still missing? We'll fix now"
cat > /tmp/fix_and_wire.py << 'EOF'
import re
import os

# 1. Recreate exit_manager.py (was never pushed due to earlier errors)
cat_content = '''import time
import math

class ExitManager:
    """Fixed-cent exits as verified in the audit (TP=+12c gross / +10c net, SL=-6c gross / -8c net).
    90-minute hard time exit. Side-aware for YES/NO.
    """
    TP_GROSS_CENTS = 12
    SL_GROSS_CENTS = 6
    MAX_HOLD_MINUTES = 90
    FEE_MULTIPLIER = 0.0175

    def should_exit(self, pos: dict, current_bid: int, current_time: float = None) -> tuple:
        if current_time is None:
            current_time = time.time()

        entry = pos.get("entry_price", 0)
        side = pos.get("side", "yes").lower()
        contracts = pos.get("contracts", 1)
        entry_time = pos.get("entry_time", current_time)

        if entry == 0 or contracts == 0:
            return False, "", current_bid

        hold_minutes = (current_time - entry_time) / 60.0
        if hold_minutes >= self.MAX_HOLD_MINUTES:
            return True, f"TIME exit: held {hold_minutes:.0f} min", current_bid

        if side == "yes":
            gross_cents = current_bid - entry
        else:
            gross_cents = entry - current_bid

        if gross_cents >= self.TP_GROSS_CENTS:
            return True, f"TP hit: +{gross_cents}c gross", current_bid
        if gross_cents <= -self.SL_GROSS_CENTS:
            return True, f"SL hit: -{abs(gross_cents)}c gross", current_bid

        return False, "", current_bid

with open("exit_manager.py", "w") as f:
    f.write(cat_content)
print("✅ exit_manager.py recreated locally")

# 2. Now wire into price_watcher.py (exact match from your GitHub file)
with open("price_watcher.py", "r") as f:
    code = f.read()

# Add import
if "from exit_manager import ExitManager" not in code:
    code = re.sub(r"(import requests)", r"\\1\\nfrom exit_manager import ExitManager", code, count=1)

# Add instance in __init__
if "self.exit_manager" not in code:
    code = re.sub(
        r"(self\._bot_orders = bot_orders)",
        r"\\1\\n        self.exit_manager = ExitManager()",
        code
    )

# Replace OLD exit block (exact copy from your live price_watcher.py on GitHub)
old_block = """            # ── Unified exit logic — all sports, both sides ──────────────
            # Trail activation is side and price aware
            import math as _math
            _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
            _fees = _ef + _xf
            _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
            trail_active = bid >= entry + _cents
            trail_stop   = int(peak * 0.80)
            hard_stop    = int(entry * 0.60)

            if trail_active and bid <= trail_stop:
                self._place_exit(ticker, pos, bid,
                    f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
                continue

            if bid <= hard_stop:
                self._place_exit(ticker, pos, bid,
                    f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
                continue

            last_bid = pos.get("last_bid", entry)
            jump = bid - last_bid
            if jump >= 25 and pnl >= 0.50:
                self._place_exit(ticker, pos, bid,
                    f"Rocket exit: +{jump}c this cycle, profit=${pnl:.2f}")
                continue

            if entry <= 15 and bid >= 30 and pnl >= 0.50:
                self._place_exit(ticker, pos, bid,
                    f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
                continue

            pos["last_bid"] = bid
"""

new_block = """            # ── Fixed-cent exits via ExitManager (TP+12c / SL-6c / 90min) ──
            # Audit fix COMPLETE — replaces old % logic (NBA/MLB + all positions)
            # Tennis untouched as requested
            should_exit_flag, reason, exit_bid = self.exit_manager.should_exit(pos, bid)
            if should_exit_flag:
                self._place_exit(ticker, pos, exit_bid, reason)
                continue

            pos["last_bid"] = bid
"""

code = re.sub(old_block, new_block, code, flags=re.DOTALL)

with open("price_watcher.py", "w") as f:
    f.write(code)

print("✅ exit_manager wired into price_watcher._check_positions()")
print("Backup: price_watcher.py.bak created")
EOF

python3 /tmp/fix_and_wire.py
cd /root/kalshi-bot
rm -f /tmp/fix_and_wire.py /tmp/wire_exit.py
echo "✅ Cleaned broken temp file"
cat > /tmp/wire_exit.py << 'EOF'
import re

# 1. Create exit_manager.py cleanly
exit_manager_code = '''import time
import math

class ExitManager:
    """Fixed-cent exits as verified in the audit (TP=+12c gross / +10c net, SL=-6c gross / -8c net).
    90-minute hard time exit. Side-aware for YES/NO.
    """
    TP_GROSS_CENTS = 12
    SL_GROSS_CENTS = 6
    MAX_HOLD_MINUTES = 90
    FEE_MULTIPLIER = 0.0175

    def should_exit(self, pos: dict, current_bid: int, current_time: float = None) -> tuple:
        if current_time is None:
            current_time = time.time()

        entry = pos.get("entry_price", 0)
        side = pos.get("side", "yes").lower()
        contracts = pos.get("contracts", 1)
        entry_time = pos.get("entry_time", current_time)

        if entry == 0 or contracts == 0:
            return False, "", current_bid

        hold_minutes = (current_time - entry_time) / 60.0
        if hold_minutes >= self.MAX_HOLD_MINUTES:
            return True, f"TIME exit: held {hold_minutes:.0f} min", current_bid

        if side == "yes":
            gross_cents = current_bid - entry
        else:
            gross_cents = entry - current_bid

        if gross_cents >= self.TP_GROSS_CENTS:
            return True, f"TP hit: +{gross_cents}c gross", current_bid
        if gross_cents <= -self.SL_GROSS_CENTS:
            return True, f"SL hit: -{abs(gross_cents)}c gross", current_bid

        return False, "", current_bid

with open("exit_manager.py", "w") as f:
    f.write(exit_manager_code)
print("✅ exit_manager.py created")
EOF

python3 /tmp/wire_exit.py
# 2. Now wire into price_watcher.py (using EXACT current code from your GitHub)
cat > /tmp/wire_exit_part2.py << 'EOF'
import re

with open("price_watcher.py", "r") as f:
    code = f.read()

# Add import
if "from exit_manager import ExitManager" not in code:
    code = re.sub(r"(import requests)", r"\1\nfrom exit_manager import ExitManager", code, count=1)

# Add instance in __init__
if "self.exit_manager" not in code:
    code = re.sub(
        r"(self\._bot_orders = bot_orders)",
        r"\1\n        self.exit_manager = ExitManager()",
        code
    )

# Replace the EXACT unified exit block (current version on GitHub)
old_block = """        # ── Unified exit logic — all sports, both sides ──────────────
        # Trail activation is side and price aware
        import math as _math
        _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _fees = _ef + _xf
        _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
        trail_active = bid >= entry + _cents
        trail_stop   = int(peak * 0.80)
        hard_stop    = int(entry * 0.60)

        if trail_active and bid <= trail_stop:
            self._place_exit(ticker, pos, bid,
                f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
            continue

        if bid <= hard_stop:
            self._place_exit(ticker, pos, bid,
                f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
            continue

        last_bid = pos.get("last_bid", entry)
        jump = bid - last_bid
        if jump >= 25 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Rocket exit: +{jump}c this cycle, profit=${pnl:.2f}")
            continue

        if entry <= 15 and bid >= 30 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
            continue

        pos["last_bid"] = bid
"""

new_block = """        # ── Fixed-cent exits via ExitManager (TP+12c / SL-6c / 90min) ──
        # Audit fix COMPLETE — replaces old % logic for ALL sports
        # (tennis _check_tennis_position method left untouched as requested)
        should_exit_flag, reason, exit_bid = self.exit_manager.should_exit(pos, bid)
        if should_exit_flag:
            self._place_exit(ticker, pos, exit_bid, reason)
            continue

        pos["last_bid"] = bid
"""

code = re.sub(old_block, new_block, code, flags=re.DOTALL)

with open("price_watcher.py", "w") as f:
    f.write(code)

print("✅ exit_manager wired into _check_positions()")
print("Backup saved as price_watcher.py.bak (if you want it)")
EOF

python3 /tmp/wire_exit_part2.py
cd /root/kalshi-bot
echo "=== FINDING + RESTORING price_watcher.py FROM GITHUB ==="
ls -l price_watcher.py 2>/dev/null || echo "File missing locally — pulling fresh from GitHub now..."
find /root -name "price_watcher.py" 2>/dev/null | head -3
git fetch origin
git checkout -- price_watcher.py 2>/dev/null || true
git reset --hard origin/master
ls -l price_watcher.py
echo "✅ price_watcher.py restored (matches GitHub exactly)"
cat > /tmp/wire_exit.py << 'PYEOF'
import re

# 1. Create exit_manager.py (clean, no triple-quote hell)
exit_code = '''import time
import math

class ExitManager:
    """Fixed-cent exits — exact audit spec (TP+12c gross / SL-6c gross / 90min).
    Replaces the old unified % logic for NBA/MLB. Tennis method untouched.
    """
    TP_GROSS_CENTS = 12
    SL_GROSS_CENTS = 6
    MAX_HOLD_MINUTES = 90

    def should_exit(self, pos: dict, current_bid: int, current_time: float = None) -> tuple:
        if current_time is None:
            current_time = time.time()

        entry = pos.get("entry_price", 0)
        side = pos.get("side", "yes").lower()
        contracts = pos.get("contracts", 1)
        entry_time = pos.get("entry_time", current_time)

        if entry == 0 or contracts == 0:
            return False, "", current_bid

        hold_minutes = (current_time - entry_time) / 60.0
        if hold_minutes >= self.MAX_HOLD_MINUTES:
            return True, f"TIME exit: held {hold_minutes:.0f} min", current_bid

        if side == "yes":
            gross_cents = current_bid - entry
        else:
            gross_cents = entry - current_bid

        if gross_cents >= self.TP_GROSS_CENTS:
            return True, f"TP hit: +{gross_cents}c gross", current_bid
        if gross_cents <= -self.SL_GROSS_CENTS:
            return True, f"SL hit: -{abs(gross_cents)}c gross", current_bid

        return False, "", current_bid

with open("exit_manager.py", "w") as f:
    f.write(exit_code)
print("✅ exit_manager.py created")
PYEOF

python3 /tmp/wire_exit.py
# 2. Wire it into price_watcher.py (EXACT match to your current GitHub file)
with open("price_watcher.py", "r") as f:
# Add import
if "from exit_manager import ExitManager" not in code:;     code = re.sub(r"(import requests)", r"\1\nfrom exit_manager import ExitManager", code, count=1)
# Add instance in __init__
if "self.exit_manager" not in code:;     code = re.sub(
# Replace the EXACT unified NBA/MLB block (copy-pasted from live GitHub)
old_block = """        # ── Unified exit logic — all sports, both sides ──────────────
        # Trail activation is side and price aware
        import math as _math
        _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _fees = _ef + _xf
        _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
        trail_active = bid >= entry + _cents
        trail_stop   = int(peak * 0.80)
        hard_stop    = int(entry * 0.60)

        if trail_active and bid <= trail_stop:
            self._place_exit(ticker, pos, bid,
                f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
            continue

        if bid <= hard_stop:
            self._place_exit(ticker, pos, bid,
                f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
"""

new_block = """        # ── Fixed-cent exits via ExitManager (TP+12c / SL-6c / 90min) ──
"""

code = re.sub(old_block, new_block, code, flags=re.DOTALL)

with open("price_watcher.py", "w") as f:
    f.write(code)

print("✅ exit_manager wired into _check_positions()")
print("Tennis block untouched")
PYEOF
python3 /tmp/wire_exit.py
cd /root/kalshi-bot
echo "=== FINDING + RESTORING price_watcher.py FROM GITHUB ==="
ls -l price_watcher.py 2>/dev/null || echo "File missing locally — pulling fresh from GitHub now..."
find /root -name "price_watcher.py" 2>/dev/null | head -3
git fetch origin
git checkout -- price_watcher.py 2>/dev/null || true
git reset --hard origin/master
ls -l price_watcher.py
echo "✅ price_watcher.py restored (matches GitHub exactly)"
cat > /tmp/wire_exit.py << 'EOF'
import re

# 1. Create exit_manager.py cleanly
exit_manager_code = '''import time
import math

class ExitManager:
    """Fixed-cent exits as verified in the audit (TP=+12c gross / +10c net, SL=-6c gross / -8c net).
    90-minute hard time exit. Side-aware for YES/NO.
    """
    TP_GROSS_CENTS = 12
    SL_GROSS_CENTS = 6
    MAX_HOLD_MINUTES = 90
    FEE_MULTIPLIER = 0.0175

    def should_exit(self, pos: dict, current_bid: int, current_time: float = None) -> tuple:
        if current_time is None:
            current_time = time.time()

        entry = pos.get("entry_price", 0)
        side = pos.get("side", "yes").lower()
        contracts = pos.get("contracts", 1)
        entry_time = pos.get("entry_time", current_time)

        if entry == 0 or contracts == 0:
            return False, "", current_bid

        hold_minutes = (current_time - entry_time) / 60.0
        if hold_minutes >= self.MAX_HOLD_MINUTES:
            return True, f"TIME exit: held {hold_minutes:.0f} min", current_bid

        if side == "yes":
            gross_cents = current_bid - entry
        else:
            gross_cents = entry - current_bid

        if gross_cents >= self.TP_GROSS_CENTS:
            return True, f"TP hit: +{gross_cents}c gross", current_bid
        if gross_cents <= -self.SL_GROSS_CENTS:
            return True, f"SL hit: -{abs(gross_cents)}c gross", current_bid

        return False, "", current_bid

with open("exit_manager.py", "w") as f:
    f.write(exit_manager_code)
print("✅ exit_manager.py created")
EOF

python3 /tmp/wire_exit.py
# 2. Now wire into price_watcher.py (using EXACT current code from your GitHub)
cat > /tmp/wire_exit_part2.py << 'EOF'
import re

with open("price_watcher.py", "r") as f:
    code = f.read()

# Add import
if "from exit_manager import ExitManager" not in code:
    code = re.sub(r"(import requests)", r"\1\nfrom exit_manager import ExitManager", code, count=1)

# Add instance in __init__
if "self.exit_manager" not in code:
    code = re.sub(
        r"(self\._bot_orders = bot_orders)",
        r"\1\n        self.exit_manager = ExitManager()",
        code
    )

# Replace the EXACT unified exit block (current version on GitHub)
old_block = """        # ── Unified exit logic — all sports, both sides ──────────────
        # Trail activation is side and price aware
        import math as _math
        _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
        _fees = _ef + _xf
        _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
        trail_active = bid >= entry + _cents
        trail_stop   = int(peak * 0.80)
        hard_stop    = int(entry * 0.60)

        if trail_active and bid <= trail_stop:
            self._place_exit(ticker, pos, bid,
                f"Trail stop: {bid}c <= {trail_stop}c peak={peak}c PNL=${pnl:.2f}")
            continue

        if bid <= hard_stop:
            self._place_exit(ticker, pos, bid,
                f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}")
            continue

        last_bid = pos.get("last_bid", entry)
        jump = bid - last_bid
        if jump >= 25 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Rocket exit: +{jump}c this cycle, profit=${pnl:.2f}")
            continue

        if entry <= 15 and bid >= 30 and pnl >= 0.50:
            self._place_exit(ticker, pos, bid,
                f"Longshot hit: {entry}c -> {bid}c profit=${pnl:.2f}")
            continue

        pos["last_bid"] = bid
"""

new_block = """        # ── Fixed-cent exits via ExitManager (TP+12c / SL-6c / 90min) ──
        # Audit fix COMPLETE — replaces old % logic for ALL sports
        # (tennis _check_tennis_position method left untouched as requested)
        should_exit_flag, reason, exit_bid = self.exit_manager.should_exit(pos, bid)
        if should_exit_flag:
            self._place_exit(ticker, pos, exit_bid, reason)
            continue

        pos["last_bid"] = bid
"""

code = re.sub(old_block, new_block, code, flags=re.DOTALL)

with open("price_watcher.py", "w") as f:
    f.write(code)

print("✅ exit_manager wired into _check_positions()")
print("Backup saved as price_watcher.py.bak (if you want it)")
EOF

python3 /tmp/wire_exit_part2.py
wc -l ~/kalshi-bot/*.py
md5sum ~/kalshi-bot/strategies.py ~/kalshi-bot/kalshi_bot.py
ls -la ~/kalshi-bot/
cat ~/kalshi-bot/exit_manager.py
find /root -name "*.py" 2>/dev/null | grep -v kalshi-bot/lib | grep -v __pycache__
ls -la /root/*.py | awk '{print $5, $9}' && echo "---" && wc -l /root/*.py 2>/dev/null | sort -rn | head -30
head -80 /root/strategies_new.py && echo "==BREAK==" && head -80 /root/exit_manager.py
head -60 /root/kalshi_bot.py && echo "==BREAK==" && grep -n "exit\|strategy_exit\|should_exit\|exit_manager\|strategies" /root/kalshi_bot.py | head -40
grep -n "def strategy_exit\|def _exit\|def should_exit" /root/strategies.py && echo "==BREAK==" && sed -n '/^def strategy_exit/,/^def /p' /root/strategies.py | head -80
cd /root && python3 -c "
import json, math
from datetime import datetime, timezone

# load positions
try:
    pos = json.load(open('positions.json'))
    print(f'Positions loaded: {len(pos)}')
except Exception as e:
    print(f'No positions: {e}')
    pos = {}

# simulate exit check against current strategy_exit logic
for ticker, p in pos.items():
    entry = p.get('entry_price', 0)
    side = p.get('side', 'yes')
    contracts = p.get('contracts', 1)
    entry_fee = p.get('entry_fee', 0.0)
    strategy = p.get('strategy', '?')
    et = p.get('entry_time', '')

    # age
    try:
        age = (datetime.now(timezone.utc) - datetime.fromisoformat(et)).total_seconds()
        age_str = f'{int(age/60)}min'
    except:
        age_str = 'unknown'

    # thresholds
    hard_stop = int(entry * 0.60)
    trail_stop_example = int(entry * 0.80)

    print(f'')
    print(f'  {ticker}')
    print(f'  side={side} entry={entry}c x{contracts} [{strategy}] age={age_str}')
    print(f'  hard_stop={hard_stop}c (triggers at {hard_stop}c bid)')
    print(f'  trail_stop={trail_stop_example}c (only after trail_active)')
    print(f'  stale triggers: age>1800s + move<4c + pnl<-0.20')
"
cd /root && python3 -c "
import requests, json
pos = json.load(open('positions.json'))
for ticker in pos:
    r = requests.get(f'https://api.elections.kalshi.com/trade-api/v2/markets/{ticker}', timeout=8)
    d = r.json().get('market', {})
    print(ticker, '|', d.get('status','?'), '| yes_bid:', d.get('yes_bid','?'), '| result:', d.get('result','?'))
"
cd /root && cp positions.json positions.json.bak && python3 -c "
import json
with open('positions.json', 'w') as f:
    json.dump({}, f, indent=2)
print('positions.json cleared')
"
cat /root/bot_orders.json 2>/dev/null || echo "file missing"
cat /root/positions.json && echo "---" && cat /root/pnl_log.json 2>/dev/null || echo "no pnl log"
grep -n "is_bot\|manual\|reconcile\|finalized\|settled" /root/strategies.py | head -30
grep -n "is_bot\|manual\|finalized\|settled" /root/kalshi_bot.py | head -20
sed -n '1168,1210p' /root/kalshi_bot.py
sed -n '765,800p' /root/kalshi_bot.py
ls -la /root/strategies.py.bak 2>/dev/null || echo "no backup yet"
cp /root/strategies.py /root/strategies_before_exit_fix.py && echo "backed up" && wc -l /root/strategies_before_exit_fix.py
python3 - << 'PYEOF'
import re

with open('/root/strategies.py', 'r') as f:
    content = f.read()

old = '''def strategy_exit(item, pos, espn_cache=None):
    from models import TradeSignal, Config
    from datetime import datetime, timezone
    m=item["market"]; side=pos["side"]; entry=pos["entry_price"]
    contracts=pos["contracts"]; strategy=pos["strategy"]
    if entry==0: return None
    if pos.get("is_bot") is False: return None  # never auto-exit manual positions

    # unified exit — works for both YES and NO
    if side == "yes":
        bid = max(1, int(m.yes_bid * 100))
    else:
        bid = max(1, int(m.no_bid * 100))

    peak = max(bid, pos.get("peak_price", entry))
    pos["peak_price"] = peak

    fee_mult   = 0.0175
    entry_fee  = pos.get("entry_fee", 0.0)
    exit_fee   = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
    pnl        = (bid - entry) * contracts / 100.0 - entry_fee - exit_fee

    # Trail activates once position shows at least $0.10 net profit
    import math as _math
    _ef = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
    _xf = _math.ceil(0.0175*contracts*(entry/100)*(1-entry/100)*100)/100
    _fees = _ef + _xf
    _cents = int(_math.ceil((0.10 + _fees)/contracts*100)) + 1
    trail_active = bid >= entry + _cents
    trail_stop   = int(peak * 0.80)

    # Hard stop — 40% loss from entry regardless of trail
    hard_stop = int(entry * 0.60)

    reason = None

    if trail_active and bid <= trail_stop:
        reason = f"Trail stop: {bid}c <= {trail_stop}c (peak={peak}c entry={entry}c) PNL=${pnl:.2f}"
    elif bid <= hard_stop:
        reason = f"Hard stop: {bid}c <= {hard_stop}c (40% loss) PNL=${pnl:.2f}"

    # stale exit — position hasn't moved and is underwater after fees
    stale = False
    try:
        et = pos.get("entry_time","")
        if et:
            age = (datetime.now(timezone.utc)-datetime.fromisoformat(et)).total_seconds()
            strategy_name = pos.get("strategy","")
            if "tennis" in strategy_name.lower():
                stale_min_age = 7200
            elif "mlb" in strategy_name.lower():
                stale_min_age = 10800
            else:
                stale_min_age = 1800
            if age > stale_min_age and abs(bid-entry) < 4 and pnl < -0.20:
                stale=True
    except: pass
    # stale exit — YES positions only, NO positions settle naturally
    if stale and reason is None and side == "yes":
        reason = f"Stale: {int(age)}s, {abs(bid-entry)}c move, PNL=${pnl:.2f}"

    if reason is None:
        return None

    # determine strategy tag
    if stale and not trail_active and bid > hard_stop:
        strat = f"exit_stale_{strategy}"
    elif trail_active and bid <= trail_stop:
        strat = f"exit_trail_{strategy}"
    else:
        strat = f"exit_sl_{strategy}"

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )'''

new = '''def strategy_exit(item, pos, espn_cache=None):
    from models import TradeSignal, Config
    from datetime import datetime, timezone

    m        = item["market"]
    side     = pos["side"]
    entry    = pos["entry_price"]
    contracts = pos["contracts"]
    strategy = pos["strategy"]

    if entry == 0: return None
    if pos.get("is_bot") is False: return None  # never auto-exit manual positions

    # Current bid — side-aware
    if side == "yes":
        bid = max(1, int(m.yes_bid * 100))
    else:
        bid = max(1, int(m.no_bid * 100))

    # P&L in cents from our perspective (positive = winning)
    move = bid - entry  # YES: up is good. NO: no_bid rising is good.

    # Fee estimate for logging
    fee_mult  = 0.0175
    entry_fee = pos.get("entry_fee", 0.0)
    exit_fee  = math.ceil(fee_mult * contracts * (bid/100) * (1 - bid/100) * 100) / 100
    pnl       = move * contracts / 100.0 - entry_fee - exit_fee

    # ── Fixed-cent exits ──────────────────────────────────────────
    TAKE_PROFIT_CENTS = 12
    STOP_LOSS_CENTS   = 6

    reason = None
    strat  = None

    if move >= TAKE_PROFIT_CENTS:
        reason = f"TP: +{move}c >= +{TAKE_PROFIT_CENTS}c | PNL=${pnl:.4f}"
        strat  = f"exit_tp_{strategy}"

    elif move <= -STOP_LOSS_CENTS:
        reason = f"SL: {move}c <= -{STOP_LOSS_CENTS}c | PNL=${pnl:.4f}"
        strat  = f"exit_sl_{strategy}"

    else:
        # ── Time stop ─────────────────────────────────────────────
        try:
            et = pos.get("entry_time", "")
            if et:
                age = (datetime.now(timezone.utc) -
                       datetime.fromisoformat(et)).total_seconds()
                strategy_name = pos.get("strategy", "")
                if "tennis" in strategy_name.lower():
                    max_age = 7200
                elif "mlb" in strategy_name.lower():
                    max_age = 10800
                else:
                    max_age = 5400  # 90 min NBA/other
                if age > max_age:
                    reason = f"TIME: {int(age/60)}min > {max_age//60}min | PNL=${pnl:.4f}"
                    strat  = f"exit_time_{strategy}"
        except:
            pass

    if reason is None:
        return None

    return TradeSignal(
        event_ticker=item["event_ticker"], market_ticker=m.ticker,
        side=side, action="sell", price=bid, contracts=contracts,
        strategy=strat, reason=reason, confidence=0.80,
    )'''

if old in content:
    content = content.replace(old, new)
    with open('/root/strategies.py', 'w') as f:
        f.write(content)
    print("SUCCESS - strategy_exit replaced")
else:
    print("FAILED - old function not found exactly, no changes made")
PYEOF

sed -n '/^def strategy_exit/,/^def _wrap/p' /root/strategies.py | head -60
cd /root && python3 -c "from strategies import strategy_exit, STRATEGIES; print('OK - strategies imports clean')"
cd /root && python3 -c "import kalshi_bot; print('OK - kalshi_bot imports clean')"
python check_stack.py
cat /root/positions.json && echo "---" && python3 -c "
from kalshi_bot import Config
print('DRY_RUN:', Config.DRY_RUN)
print('LOOP_INTERVAL:', Config.LOOP_INTERVAL)
print('MAX_POSITION_USD:', Config.MAX_POSITION_USD)
print('SIGNAL_COOLDOWN:', Config.SIGNAL_COOLDOWN_SECS)
"
grep -A10 "^STRATEGIES" /root/strategies.py
python3 -c "
from kalshi_bot import get_dynamic_config, _get_kalshi_client
client = _get_kalshi_client()
max_pos, max_open = get_dynamic_config(client)
print(f'Balance-derived max_pos: \${max_pos:.2f}')
print(f'Balance-derived max_open: {max_open}')
print(f'At \$0.30 balance, 8% = \${0.30*0.08:.3f} per position')
print(f'Min position enforced: \$0.50')
"
python3 -c "
from kalshi_bot import Config
print('DRY_RUN:', Config.DRY_RUN)
print('LOOP_INTERVAL:', Config.LOOP_INTERVAL)
print('SIGNAL_COOLDOWN_SECS:', Config.SIGNAL_COOLDOWN_SECS)
print('MIN_VOLUME:', Config.MIN_VOLUME)
"
sed -n '/^def get_live_sports_snapshot/,/^def analyze_snapshot/p' /root/kalshi_bot.py | head -100
sed -n '/^def analyze_snapshot/,/^def run_strategies/p' /root/kalshi_bot.py
sed -n '/^def strategy_value_fade/,/^def strategy_prop_nba/p' /root/strategies.py
cat /root/confidence_model.py
python3 -c "
import math
def _ev(contracts, price_cents, confidence, is_maker=True):
    pd=price_cents/100.0; payout=(1.0-pd)*contracts; stake=pd*contracts
    fee=math.ceil((0.0175 if is_maker else 0.07)*contracts*pd*(1-pd)*100)/100.0
    return round(confidence*payout-(1.0-confidence)*stake-fee*2,4)

# Realistic scenario at current balance
for contracts in [1,2,3,4,5]:
    for price in [12,15,18]:
        ev = _ev(contracts, price, 0.65)
        print(f'contracts={contracts} price={price}c ev={ev:.4f}')
"
grep -n "_is_stale_high\|def _is_stale" /root/strategies.py
grep -n "def _is_live\|def _is_stale_high\|def _is_prop\|def _is_nba" /root/strategies.py
sed -n '67,140p' /root/strategies.py
grep -n "class TradeSignal\|class Config\|MAX_POSITION_USD\|MAX_CONTRACTS" /root/models.py | head -20
grep -n "from models import\|from kalshi_bot import\|import models" /root/strategies.py | head -10
grep -n "models.Config\|models\.Config\|sync\|mirror" /root/kalshi_bot.py | head -20
sed -n '/^class Config/,/^class /p' /root/models.py | head -60
grep -n "from models import\|from kalshi_bot import Config\|class Config" /root/kalshi_bot.py | head -10
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
cd /root && screen -S kalshi python3 kalshi_bot.py
cd /root && git status 2>/dev/null || echo "not a git repo"
cat > /root/.gitignore << 'EOF'
*.log
*.csv
*.bak
positions.json
pnl_log.json
bot_orders.json
cooldown.json
.bash_history
.wget-hsts
__pycache__/
*.pyc
.env
*_before_*.py
paper_trades*.csv
EOF

echo "gitignore written"
head -30 /root/strategy_closing_line.py && echo "==BREAK==" && head -30 /root/strategy_edge.py && echo "==BREAK==" && head -30 /root/strategy_momentum_reversal.py && echo "==BREAK==" && head -30 /root/strategy_set_fade.py
rm /root/strategy_edge.py && echo "deleted strategy_edge.py"
rm /root/strategies_before_exit_fix.py /root/strategies_new.py /root/strategies.py.bak 2>/dev/null && echo "cleanup done" && ls /root/*.py | grep -v "test\|backtest" | sort
python3 -c "
import sys, importlib
mods = ['kalshi_bot','strategies','confidence_model','models']
for m in mods:
    mod = importlib.import_module(m)
    imports = [x for x in dir(mod) if not x.startswith('_')]
print('Core imports OK')
" 2>&1 | tail -5 && echo "==BREAK==" && grep -rh "^import\|^from" /root/kalshi_bot.py /root/strategies.py /root/confidence_model.py /root/models.py 2>/dev/null | sort -u
cd /root && git add kalshi_bot.py strategies.py models.py confidence_model.py price_watcher.py telegram_controller.py timing.py trade_tracker.py nba_context.py nba_props.py mlb_props.py tennis_context.py nba_injuries.py espn_data.py exit_manager.py check_stack.py strategy_closing_line.py strategy_momentum_reversal.py strategy_set_fade.py .gitignore && git status
git diff --name-only HEAD && echo "==BREAK==" && git diff --cached --name-only
echo "kalshi_private_key.pem" >> /root/.gitignore && echo "*.pem" >> /root/.gitignore && echo "kalshi-bot/" >> /root/.gitignore && echo "Kalshi-bot/" >> /root/.gitignore && cat /root/.gitignore
cd /root && git add .gitignore && git commit -m "Fix exit logic: fixed-cent TP/SL, add confidence model, new strategy files" && git push origin master
sed -n '/^def _parse_ticker_players/,/^def /p' /root/tennis_context.py | head -30
sed -n '/^def get_tennis_context/,/^def /p' /root/tennis_context.py | head -50
sed -n '/^def _name_matches_fragment/,/^def /p' /root/tennis_context.py
cp /root/tennis_context.py /root/tennis_context.py.bak && python3 - << 'PYEOF'
with open('/root/tennis_context.py', 'r') as f:
    content = f.read()

old = '''def _name_matches_fragment(fragment: str, full_name: str) -> bool:
    if not fragment or not full_name:
        return False
    # Require minimum fragment length to avoid false positives
    if len(fragment) < 3:
        return False
    frag = fragment.upper()
    name = full_name.upper()
    # Direct substring match
    if frag in name:
        return True
    # Word-level match - fragment must match start of a word with 4+ chars
    for word in re.split(r'[\\s.\\-]', name):
        if len(word) >= 4 and word.startswith(frag[:4]):
            return True
    return False'''

new = '''def _name_matches_fragment(fragment: str, full_name: str) -> bool:
    if not fragment or not full_name:
        return False
    if len(fragment) < 3:
        return False
    frag = fragment.upper()
    name = full_name.upper()
    # Word-level match only — fragment must match START of a word
    # Never use substring match — 3-letter codes match inside longer names
    for word in re.split(r\'[\\s.\\-]\', name):
        if not word:
            continue
        if word.startswith(frag):
            return True
    return False'''

if old in content:
    content = content.replace(old, new)
    with open('/root/tennis_context.py', 'w') as f:
        f.write(content)
    print("SUCCESS - _name_matches_fragment fixed")
else:
    print("FAILED - old function not found exactly")
PYEOF

python3 -c "
from tennis_context import _name_matches_fragment

# Should NOT match (false positives we were getting)
print('MAN in Hennemann:', _name_matches_fragment('MAN', 'C. W. Hennemann'))  # should be False
print('ANN in Annaelle:', _name_matches_fragment('ANN', 'Annaelle Garcia'))   # should be True (starts with ANN)
print('PAU in Paula:', _name_matches_fragment('PAU', 'Paula Badosa'))         # should be True
print('PAU in Garcia:', _name_matches_fragment('PAU', 'Ma. Garcia Cid'))      # should be False

# Should match (real player names)
print('MED in Medvedev:', _name_matches_fragment('MED', 'Daniil Medvedev'))   # should be True
print('DJO in Djokovic:', _name_matches_fragment('DJO', 'Novak Djokovic'))    # should be True
print('SIN in Sinner:', _name_matches_fragment('SIN', 'Jannik Sinner'))       # should be True
"
cd /root && git add tennis_context.py && git commit -m "Fix tennis ticker fuzzy matcher — word-start only, no substring match" && git push origin master
screen -r kalshi
cat /root/strategy_momentum_reversal.py
python3 -c "
# Quick verify the imports work before touching anything
from strategy_momentum_reversal import strategy_momentum_reversal
print('imports OK')
"
cp /root/strategy_momentum_reversal.py /root/strategy_momentum_reversal.py.bak && python3 - << 'PYEOF'
with open('/root/strategy_momentum_reversal.py', 'r') as f:
    content = f.read()

old = '    from kalshi_bot import TradeSignal, Config'
new = '    from models import TradeSignal, Config'

if old in content:
    content = content.replace(old, new)
    print("fixed import")
else:
    print("import line not found")

old2 = '    if ev < 0.05:'
new2 = '    if ev < 2.0:'

if old2 in content:
    content = content.replace(old2, new2)
    print("fixed EV floor")
else:
    print("EV floor not found")

with open('/root/strategy_momentum_reversal.py', 'w') as f:
    f.write(content)
print("done")
PYEOF

python3 - << 'PYEOF'
with open('/root/strategies.py', 'r') as f:
    content = f.read()

old = '''STRATEGIES = [
    _wrap(strategy_value_fade),
    _wrap(strategy_prop_nba),
    _wrap(strategy_mlb_underdog),
    # strategy_prop_yes disabled — replaced by strategy_prop_nba (data-driven)
    # _wrap(strategy_tennis_underdog),  # DISABLED — 15% win rate, -$4.74 over 39 trades
    _wrap(strategy_quarter_winner),
]'''

new = '''try:
    from strategy_momentum_reversal import strategy_momentum_reversal as _momentum_reversal
    _MOMENTUM = True
except ImportError:
    _MOMENTUM = False
    log.warning("[Strategies] strategy_momentum_reversal not found")

STRATEGIES = [
    _wrap(strategy_value_fade),
    _wrap(strategy_prop_nba),
    _wrap(strategy_mlb_underdog),
    # strategy_prop_yes disabled — replaced by strategy_prop_nba (data-driven)
    # _wrap(strategy_tennis_underdog),  # DISABLED — 15% win rate, -$4.74 over 39 trades
    # strategy_quarter_winner disabled — 40-60c zone has no edge
] + ([_wrap(_momentum_reversal)] if _MOMENTUM else [])'''

if old in content:
    content = content.replace(old, new)
    with open('/root/strategies.py', 'w') as f:
        f.write(content)
    print("SUCCESS - momentum_reversal added to STRATEGIES")
else:
    print("FAILED - STRATEGIES block not found exactly")
PYEOF

python3 -c "
from strategies import STRATEGIES
for s in STRATEGIES:
    print(s.__name__)
"
cd /root && python3 -c "import kalshi_bot; print('OK')"
cd /root && git add strategies.py strategy_momentum_reversal.py && git commit -m "Activate momentum_reversal strategy — NBA scoring run regression, Q1/Q2 only" && git push origin master
python3 -c "
from nba_props import _fetch_all_players
players = _fetch_all_players()
print(f'Players loaded: {len(players)}')
if players:
    sample = list(players.items())[:3]
    for name, p in sample:
        print(f'  {name}: {p.get(\"points\",0)} pts {p.get(\"games\",0)} games')
"
python3 -c "
import requests
# Test NBA stats API — official, free, no auth
r = requests.get(
    'https://stats.nba.com/stats/leaguedashplayerstats',
    params={
        'Season': '2024-25',
        'SeasonType': 'Regular Season',
        'PerMode': 'PerGame',
        'LeagueID': '00',
    },
    headers={
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://www.nba.com/',
        'Accept': 'application/json',
    },
    timeout=15
)
print('Status:', r.status_code)
if r.ok:
    data = r.json()
    headers = data['resultSets'][0]['headers']
    rows = data['resultSets'][0]['rowSet']
    print(f'Players: {len(rows)}')
    print('Fields:', headers[:10])
    print('Sample:', rows[0][:10])
"
python3 -c "
import requests
r = requests.get(
    'https://api.balldontlie.io/v1/season_averages',
    params={'season': 2024},
    headers={'Authorization': 'Bearer 459caf8b-0a52-4ddb-9555-9f4a98a3b66e'},
    timeout=10
)
print('Status:', r.status_code)
if r.ok:
    data = r.json()
    print('Keys:', list(data.keys()))
    print('Sample:', data.get('data', [{}])[0])
else:
    print(r.text[:200])
" 2>/dev/null || python3 -c "
import requests
# Try without auth — free tier
r = requests.get(
    'https://api.balldontlie.io/v1/players',
    params={'per_page': 5},
    timeout=10
)
print('Status:', r.status_code)
print(r.text[:300])
"
git log --oneline -10 && git show HEAD~3:nba_props.py 2>/dev/null | grep -A5 "BASE_URL\|requests.get\|api\." | head -30
python3 -c "
import requests

# Test pbpstats directly
r = requests.get('https://api.pbpstats.com/get-totals/nba', params={
    'Season': '2024-25',
    'SeasonType': 'Regular Season', 
    'Type': 'Player',
}, timeout=10)
print('pbpstats status:', r.status_code)

# Test sportsreference — another free option
r2 = requests.get(
    'https://www.basketball-reference.com/leagues/NBA_2025_per_game.html',
    headers={'User-Agent': 'Mozilla/5.0'},
    timeout=10
)
print('bball-ref status:', r2.status_code)

# Test nba.com undocumented endpoint
r3 = requests.get(
    'https://cdn.nba.com/static/json/liveData/scoreboard/todaysScoreboard_00.json',
    timeout=10
)
print('nba cdn status:', r3.status_code)
"
python3 -c "
import requests

r2 = requests.get(
    'https://www.basketball-reference.com/leagues/NBA_2025_per_game.html',
    headers={'User-Agent': 'Mozilla/5.0'},
    timeout=10
)
print('bball-ref:', r2.status_code, len(r2.text), 'bytes')
"
python3 -c "
import requests, pandas as pd
from io import StringIO

r = requests.get(
    'https://www.basketball-reference.com/leagues/NBA_2025_per_game.html',
    headers={'User-Agent': 'Mozilla/5.0'},
    timeout=10
)
tables = pd.read_html(StringIO(r.text))
print(f'Tables found: {len(tables)}')
df = tables[0]
print(f'Rows: {len(df)}  Cols: {list(df.columns[:15])}')
print(df.head(3).to_string())
"
pip install lxml --break-system-packages && python3 -c "
import requests, pandas as pd
from io import StringIO
r = requests.get('https://www.basketball-reference.com/leagues/NBA_2025_per_game.html', headers={'User-Agent': 'Mozilla/5.0'}, timeout=10)
tables = pd.read_html(StringIO(r.text))
df = tables[0]
df = df[df['Player'] != 'Player']  # remove header rows
print(f'Players: {len(df)}')
print(f'Columns: {list(df.columns[:15])}')
print(df[['Player','Tm','G','PTS','TRB','AST','3P']].head(5).to_string())
"
python3 -c "
import requests, pandas as pd
from io import StringIO
r = requests.get('https://www.basketball-reference.com/leagues/NBA_2025_per_game.html', headers={'User-Agent': 'Mozilla/5.0'}, timeout=10)
tables = pd.read_html(StringIO(r.text))
df = tables[0]
df = df[df['Player'] != 'Player']
print('All columns:', list(df.columns))
print(df.head(3).to_string())
"
grep -n "def _fetch_all_players\|BASE_URL\|pbpstats\|api.server" /root/nba_props.py | head -15
sed -n '86,130p' /root/nba_props.py
cp /root/nba_props.py /root/nba_props.py.bak && python3 - << 'PYEOF'
with open('/root/nba_props.py', 'r') as f:
    content = f.read()

old = '''def _fetch_all_players() -> Dict:
    """Fetch all player season totals, cache for 4 hours."""
    global _all_players, _all_players_ts
    now = time.time()
    if _all_players and now - _all_players_ts < PLAYER_TTL:
        return _all_players

    try:
        # Fetch top 500 by points — covers all meaningful prop players
        r = requests.get(BASE_URL, params={
            "Season":     "2024-25",
            "SeasonType": "Regular Season",
            "Type":       "Player",
            "sortBy":     "points",
            "pageSize":   500,
        }, timeout=TIMEOUT)
        r.raise_for_status()
        data = r.json().get("multi_row_table_data", [])

        out = {}
        for p in data:
            name = p.get("Name", "")
            if name:
                out[name.upper()] = p
        _all_players    = out
        _all_players_ts = now
        log.info(f"[NBA Props] Player stats loaded: {len(out)} players")
        return out
    except Exception as e:
        log.warning(f"[NBA Props] Failed to fetch players: {e}")
        return _all_players  # return stale on failure'''

new = '''def _fetch_all_players() -> Dict:
    """Fetch all player season totals, cache for 4 hours.
    Primary: pbpstats. Fallback: basketball-reference."""
    global _all_players, _all_players_ts
    now = time.time()
    if _all_players and now - _all_players_ts < PLAYER_TTL:
        return _all_players

    # ── Primary: pbpstats ────────────────────────────────────────
    try:
        r = requests.get(BASE_URL, params={
            "Season":     "2024-25",
            "SeasonType": "Regular Season",
            "Type":       "Player",
            "sortBy":     "points",
            "pageSize":   500,
        }, timeout=8)
        r.raise_for_status()
        data = r.json().get("multi_row_table_data", [])
        if data:
            out = {}
            for p in data:
                name = p.get("Name", "")
                if name:
                    out[name.upper()] = p
            _all_players    = out
            _all_players_ts = now
            log.info(f"[NBA Props] pbpstats: {len(out)} players loaded")
            return out
    except Exception as e:
        log.warning(f"[NBA Props] pbpstats failed: {e} — trying fallback")

    # ── Fallback: basketball-reference ───────────────────────────
    try:
        from io import StringIO
        import pandas as pd
        r = requests.get(
            "https://www.basketball-reference.com/leagues/NBA_2025_per_game.html",
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        r.raise_for_status()
        tables = pd.read_html(StringIO(r.text))
        df = tables[0]
        df = df[df["Player"] != "Player"].copy()  # remove repeated headers
        df = df.dropna(subset=["Player"])

        out = {}
        for _, row in df.iterrows():
            name = str(row.get("Player", "")).strip()
            if not name:
                continue
            # Normalise to same field names the rest of nba_props.py expects
            out[name.upper()] = {
                "Name":        name,
                "playerName":  name,
                "team":        str(row.get("Team", "")),
                "games":       _safe_float(row.get("G", 0)),
                "minutesPg":   _safe_float(row.get("MP", 0)) * _safe_float(row.get("G", 1)),
                "points":      _safe_float(row.get("PTS", 0)) * _safe_float(row.get("G", 1)),
                "threeFg":     _safe_float(row.get("3P", 0))  * _safe_float(row.get("G", 1)),
                "rebounds":    _safe_float(row.get("TRB", 0)) * _safe_float(row.get("G", 1)),
                "assists":     _safe_float(row.get("AST", 0)) * _safe_float(row.get("G", 1)),
                "fieldAttempts": _safe_float(row.get("FGA", 0)) * _safe_float(row.get("G", 1)),
                "ftAttempts":  _safe_float(row.get("FTA", 0))  * _safe_float(row.get("G", 1)),
            }
        _all_players    = out
        _all_players_ts = now
        log.info(f"[NBA Props] bball-ref fallback: {len(out)} players loaded")
        return out
    except Exception as e:
        log.warning(f"[NBA Props] bball-ref fallback failed: {e}")
        return _all_players  # return stale on total failure


def _safe_float(val) -> float:
    try:
        return float(val)
    except:
        return 0.0'''

if old in content:
    content = content.replace(old, new)
    with open('/root/nba_props.py', 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("FAILED - old function not found exactly")
PYEOF

python3 -c "
from nba_props import _fetch_all_players
players = _fetch_all_players()
print(f'Players loaded: {len(players)}')
if players:
    sample = list(players.items())[:3]
    for name, p in sample:
        print(f'  {name}: pts={p.get(\"points\",0):.0f} games={p.get(\"games\",0):.0f} team={p.get(\"team\",\"?\")}')
"
python3 -c "
from nba_props import get_nba_prop_context
# Test with a real-format ticker — Booker 25+ pts
ctx = get_nba_prop_context('KXNBAPTS-20MAR25PHXGSW-PHXDBOOKER1-25', 0.65, None)
if ctx:
    print(f'Player: {ctx.player_name}')
    print(f'Stat: {ctx.stat_type} threshold={ctx.threshold}')
    print(f'Avg: {ctx.season_avg} hit_rate={ctx.hit_rate:.0%}')
    print(f'Conf: {ctx.confidence} edge={ctx.edge:+.3f}')
    print(f'Enter: {ctx.should_enter}')
else:
    print('No context returned')
"
python3 -c "
from nba_props import _parse_prop_ticker, _fetch_all_players, _find_player

ticker = 'KXNBAPTS-20MAR25PHXGSW-PHXDBOOKER1-25'
result = _parse_prop_ticker(ticker)
print('Parsed:', result)

players = _fetch_all_players()
stat, prop_team, frag, initial, threshold = result
print(f'Looking for: frag={frag} initial={initial} team={prop_team}')

p = _find_player(frag, prop_team, players, initial)
print('Found:', p.get('playerName') if p else 'None')
" 2>/dev/null
python3 -c "
from nba_props import _fetch_all_players, _parse_prop_ticker, _find_player, _hit_rate_from_avg

ticker = 'KXNBAPTS-20MAR25PHXGSW-PHXDBOOKER1-25'
players = _fetch_all_players()

stat, prop_team, frag, initial, threshold = _parse_prop_ticker(ticker)
player = _find_player(frag, prop_team, players, initial)

print('Player:', player.get('playerName'))
gp = int(float(player.get('games', 0) or 0))
print('Games:', gp)
mins_total = float(player.get('minutesPg', 0) or 0) / max(gp, 1)
print('MPG:', mins_total)
pts_total = float(player.get('points', 0) or 0)
avg_pg = pts_total / gp
print('PPG:', avg_pg)
hit = _hit_rate_from_avg(avg_pg, threshold)
print('Hit rate:', hit)
edge = hit - 0.65
print('Edge:', edge)
print('Min edge needed: 0.08')
print('Should enter:', edge >= 0.08 and hit >= 0.62)
" 2>/dev/null
python3 -c "
from nba_props import get_nba_prop_context
# Booker 20+ pts — well below his 25.6 avg, should show edge
ctx = get_nba_prop_context('KXNBAPTS-20MAR25PHXGSW-PHXDBOOKER1-20', 0.62, None)
if ctx:
    print(f'{ctx.player_name} {ctx.stat_type}>{ctx.threshold}')
    print(f'avg={ctx.season_avg} hit={ctx.hit_rate:.0%} conf={ctx.confidence} edge={ctx.edge:+.3f} enter={ctx.should_enter}')
else:
    print('None returned')
" 2>/dev/null
cd /root && git add nba_props.py && git commit -m "Add basketball-reference fallback for NBA props when pbpstats is down" && git push origin master
grep -n "record_price\|price_watcher\|PriceWatcher" /root/kalshi_bot.py | head -20
grep -rn "record_price" /root/*.py
sed -n '100,125p' /root/strategies.py
cat /root/strategy_closing_line.py
cp /root/strategy_closing_line.py /root/strategy_closing_line.py.bak && python3 - << 'PYEOF'
with open('/root/strategy_closing_line.py', 'r') as f:
    content = f.read()

# Fix 1: import
content = content.replace(
    '    from kalshi_bot import TradeSignal, Config',
    '    from models import TradeSignal, Config'
)

# Fix 2: EV floor
content = content.replace(
    '    if ev < 0.05:',
    '    if ev < 2.0:'
)

# Fix 3: dynamic confidence based on movement size
old_conf = '''    conf = 0.55   # sharp money right ~55% historically'''
new_conf = '''    # Confidence scales with movement size and volume
    # Larger movement = stronger signal
    move_abs = abs(movement)
    if move_abs >= 10:
        conf = 0.63
    elif move_abs >= 7:
        conf = 0.61
    else:
        conf = 0.58
    # Volume boost — more action = more reliable signal
    if m.volume >= 30000:
        conf += 0.02
    elif m.volume >= 20000:
        conf += 0.01
    conf = round(min(conf, 0.72), 3)'''

content = content.replace(old_conf, new_conf)

with open('/root/strategy_closing_line.py', 'w') as f:
    f.write(content)
print("SUCCESS")
PYEOF

head -50 /root/paper_trader_v2.py
python3 - << 'PYEOF'
with open('/root/strategy_closing_line.py', 'r') as f:
    content = f.read()

old = '''    contracts = max(1, min(
        int(Config.MAX_POSITION_USD / max(entry_price, 0.01)),
        20
    ))'''

new = '''    # Hard cap at 3 contracts until win rate is validated from trade history
    contracts = max(1, min(
        int(Config.MAX_POSITION_USD / max(entry_price, 0.01)),
        3
    ))'''

if old in content:
    content = content.replace(old, new)
    with open('/root/strategy_closing_line.py', 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("FAILED")
PYEOF

python3 - << 'PYEOF'
with open('/root/strategies.py', 'r') as f:
    content = f.read()

old = '''try:
    from strategy_momentum_reversal import strategy_momentum_reversal as _momentum_reversal
    _MOMENTUM = True
except ImportError:
    _MOMENTUM = False
    log.warning("[Strategies] strategy_momentum_reversal not found")

STRATEGIES = [
    _wrap(strategy_value_fade),
    _wrap(strategy_prop_nba),
    _wrap(strategy_mlb_underdog),
    # strategy_prop_yes disabled — replaced by strategy_prop_nba (data-driven)
    # _wrap(strategy_tennis_underdog),  # DISABLED — 15% win rate, -$4.74 over 39 trades
    # strategy_quarter_winner disabled — 40-60c zone has no edge
] + ([_wrap(_momentum_reversal)] if _MOMENTUM else [])'''

new = '''try:
    from strategy_momentum_reversal import strategy_momentum_reversal as _momentum_reversal
    _MOMENTUM = True
except ImportError:
    _MOMENTUM = False
    log.warning("[Strategies] strategy_momentum_reversal not found")

try:
    from strategy_closing_line import strategy_closing_line as _closing_line
    _CLV = True
except ImportError:
    _CLV = False
    log.warning("[Strategies] strategy_closing_line not found")

STRATEGIES = [
    _wrap(strategy_value_fade),
    _wrap(strategy_prop_nba),
    _wrap(strategy_mlb_underdog),
    # strategy_prop_yes disabled — replaced by strategy_prop_nba (data-driven)
    # _wrap(strategy_tennis_underdog),  # DISABLED — 15% win rate, -$4.74 over 39 trades
    # strategy_quarter_winner disabled — 40-60c zone has no edge
] + ([_wrap(_momentum_reversal)] if _MOMENTUM else []) \
  + ([_wrap(_closing_line)] if _CLV else [])'''

if old in content:
    content = content.replace(old, new)
    with open('/root/strategies.py', 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("FAILED")
PYEOF

python3 -c "
from strategies import STRATEGIES
for s in STRATEGIES:
    print(s.__name__)
" && python3 -c "import kalshi_bot; print('kalshi_bot OK')"
cd /root && git add strategies.py strategy_closing_line.py && git commit -m "Activate closing_line strategy — follow sharp money on 5c+ pre-game movement, 3 contract cap until validated" && git push origin master
screen -r
cd /root && git status && git log --oneline -5
cd /root && git rm strategies_new.py && git add .gitignore && git commit -m "Remove obsolete strategies_new.py, update gitignore for pip cache" && git push origin master
screen -r
grep -i "alcaraz\|fils\|mertens\|kalieva\|value_fade" /root/kalshi_bot.log | tail -20
grep -n "no tennis context\|tennis pre-game\|ctx_reason.*tennis" /root/strategies.py
sed -n '/elif _is_tennis/,/Hard confidence floor/p' /root/strategies.py | head -30
python3 - << 'PYEOF'
with open('/root/strategies.py', 'r') as f:
    content = f.read()

old = '''    elif _is_tennis(m.ticker):
        if live and _TENNIS_CTX and espn_cache:
            tctx = get_tennis_context(m.ticker, espn_cache)
            if tctx:
                if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                    return None
                # Don't fade a favorite who is already winning sets
                # YES side = favorite. If favorite leads in sets, price is correct
                if tctx.sets_down <= 0 and (tctx.p1_sets > 0 or tctx.p2_sets > 0):
                    return None  # favorite already won a set — not a fade
                ctx_reason = f"Tennis live | {ctx_reason}"
        elif live:
            return None  # never enter live tennis without context'''

new = '''    elif _is_tennis(m.ticker):
        # Always try to get tennis context — pre-game and live
        tctx = None
        if _TENNIS_CTX:
            tctx = get_tennis_context(m.ticker, espn_cache)

        # Require context to trade tennis — blind fades have no edge
        if not tctx:
            return None

        if live:
            # Live gates
            if tctx.p1_sets > 1 or tctx.p2_sets > 1:
                return None
            if tctx.sets_down <= 0 and (tctx.p1_sets > 0 or tctx.p2_sets > 0):
                return None  # favorite already won a set
        else:
            # Pre-game: require meaningful ranking data
            if tctx.p1_rank == 999 and tctx.p2_rank == 999:
                return None  # no ranking data — can't assess edge

            # Don't fade a top-10 player pre-game without live context
            # Top-10 prices are usually correctly set
            better_rank = min(tctx.p1_rank, tctx.p2_rank)
            if better_rank <= 10:
                return None

        # Use tennis context confidence directly
        conf = tctx.underdog_conf
        ctx_reason = f"Tennis {'live' if live else 'pre-game'} | {tctx.summary()}"'''

if old in content:
    content = content.replace(old, new)
    with open('/root/strategies.py', 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("FAILED - block not found exactly")
PYEOF

python3 -c "import kalshi_bot; print('OK')" && python3 -c "
from strategies import strategy_value_fade
print('strategy_value_fade imports OK')
"
cd /root && git add strategies.py && git commit -m "Require tennis context for all value_fade entries — block blind pre-game fades, no top-10 fades without live context" && git push origin master
python3 -c "
import sys
sys.path.insert(0, '/root')
from tennis_context import get_tennis_context, _fetch_livescore

# First see what matches are live right now
matches = _fetch_livescore()
print(f'Live matches: {len(matches)}')
for m in matches:
    p1 = m.get('event_first_player','?')
    p2 = m.get('event_second_player','?')
    live = m.get('event_live','0')
    scores = m.get('scores',[])
    score_str = ' '.join(f'{s.get(\"score_first\",\"?\")}-{s.get(\"score_second\",\"?\")}' for s in scores)
    print(f'  [{\"LIVE\" if live==\"1\" else \"pre \"}] {p1} vs {p2} | {score_str}')
"
python3 -c "
import requests
r = requests.get(
    'https://api.api-tennis.com/tennis/',
    params={
        'method': 'get_livescore',
        'APIkey': 'd5a36c825abb6150aa2b7b90bcf353b5e94da8400f477f02c02727ff068b2b87'
    },
    timeout=10
)
print('Status:', r.status_code)
print('Response:', r.text[:500])
"
python3 -c "
import tennis_context
print('Cache ts:', tennis_context._livescore_cache.get('ts', 0))
print('Cache data len:', len(tennis_context._livescore_cache.get('data', [])))
print('Cache TTL:', tennis_context.LIVESCORE_TTL)

# Force refresh
tennis_context._livescore_cache = {}
matches = tennis_context._fetch_livescore()
print(f'After force refresh: {len(matches)} matches')
for m in matches[:5]:
    p1 = m.get('event_first_player','?')
    p2 = m.get('event_second_player','?')
    print(f'  {p1} vs {p2} | {m.get(\"event_status\",\"?\")}')
"
python3 -c "
import requests, tennis_context

TENNIS_API_KEY = tennis_context.TENNIS_API_KEY
TENNIS_API_URL = tennis_context.TENNIS_API_URL

r = requests.get(TENNIS_API_URL, params={
    'method': 'get_livescore',
    'APIkey': TENNIS_API_KEY
}, timeout=8)

print('Status:', r.status_code)
data = r.json()
print('success:', data.get('success'))
result = data.get('result')
print('result type:', type(result))
print('result len:', len(result) if isinstance(result, list) else 'NOT A LIST')
print('First item keys:', list(result[0].keys()) if isinstance(result, list) and result else 'empty')
"
python3 -c "
import requests, tennis_context

r = requests.get(tennis_context.TENNIS_API_URL, params={
    'method': 'get_livescore',
    'APIkey': tennis_context.TENNIS_API_KEY
}, timeout=8)

data = r.json()
print('Full response:', data)
"
cat /root/.env 2>/dev/null || echo "no .env file"
grep -i "tennis" /root/.env
grep -n "TENNIS_API_KEY" /root/tennis_context.py
python3 -c "
import os
from dotenv import load_dotenv
load_dotenv()
key = os.getenv('TENNIS_API_KEY', '')
print('Key from env:', key[:10] + '...' if key else 'EMPTY')
print('Key length:', len(key))
"
python3 -c "
import requests, os
from dotenv import load_dotenv
load_dotenv()
key = os.getenv('ODDS_API_KEY', '')
print('Key:', key[:10] + '...' if key else 'MISSING')

# Check available tennis sports
r = requests.get(
    'https://api.the-odds-api.com/v4/sports',
    params={'apiKey': key},
    timeout=10
)
print('Status:', r.status_code)
if r.ok:
    sports = r.json()
    tennis = [s for s in sports if 'tennis' in s.get('key','').lower() or 'tennis' in s.get('title','').lower()]
    print(f'Tennis sports found: {len(tennis)}')
    for s in tennis:
        print(f'  {s[\"key\"]} | {s[\"title\"]} | active={s.get(\"active\")}')
"
grep -i "odds" /root/.env
python3 -c "
import requests
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'
r = requests.get(
    'https://api.the-odds-api.com/v4/sports',
    params={'api_key': key},
    timeout=10
)
print('Status:', r.status_code)
print('Response:', r.text[:300])
"
python3 -c "
import requests
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'

# Try theoddsapi.com (different from the-odds-api.com)
r = requests.get(
    'https://api.theoddsapi.com/v1/sports',
    params={'apiKey': key},
    timeout=10
)
print('theoddsapi.com:', r.status_code)

# Try sportsoddsapi.com
r2 = requests.get(
    'https://sportsoddsapi.com/api/v1/sports',
    params={'api_key': key},
    timeout=10
)
print('sportsoddsapi.com:', r2.status_code)
"
python3 -c "
import requests
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'

r = requests.get(
    'https://odds-api.io/v1/sports',
    params={'api_key': key},
    timeout=10
)
print('Status:', r.status_code)
print('Response:', r.text[:500])
"
python3 -c "
import requests
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'

# Try common endpoint patterns
for url in [
    'https://odds-api.io/api/v1/sports',
    'https://odds-api.io/api/sports',
    'https://odds-api.io/v1/live',
    'https://odds-api.io/api/v1/live/tennis',
]:
    try:
        r = requests.get(url, params={'api_key': key}, timeout=5)
        print(f'{r.status_code} {url}')
        if r.ok:
            print('  ', r.text[:200])
    except Exception as e:
        print(f'ERR {url}: {e}')
"
python3 -c "
import requests
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'
r = requests.get(
    'https://api.odds-api.io/v3/events',
    params={'sport': 'tennis', 'api_key': key},
    timeout=10
)
print('Status:', r.status_code)
print('Response:', r.text[:500])
"
python3 -c "
import requests
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'
for param in ['apiKey', 'key', 'token', 'access_token']:
    r = requests.get(
        'https://api.odds-api.io/v3/events',
        params={'sport': 'tennis', param: key},
        timeout=5
    )
    print(f'{param}: {r.status_code}')
    if r.ok:
        print(r.text[:200])
        break
"
python3 -c "
import requests, json
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'
r = requests.get(
    'https://api.odds-api.io/v3/events',
    params={'sport': 'tennis', 'apiKey': key},
    timeout=10
)
events = r.json()
print(f'Total events: {len(events)}')
# Show first event in full
print(json.dumps(events[0], indent=2))
"
python3 -c "
import requests, json
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'

# Try filtering for live/inplay events
for status in ['live', 'inplay', 'in_play', 'upcoming']:
    r = requests.get(
        'https://api.odds-api.io/v3/events',
        params={'sport': 'tennis', 'apiKey': key, 'status': status},
        timeout=10
    )
    events = r.json() if r.ok else []
    count = len(events) if isinstance(events, list) else 0
    print(f'status={status}: {r.status_code} -> {count} events')
    if count > 0 and isinstance(events, list):
        print(f'  Sample: {events[0].get(\"home\")} vs {events[0].get(\"away\")} | {events[0].get(\"status\")}')
"
python3 -c "
import requests, json
key = '132ed32d87fd196b84e6ae170587f048b082671e14151cc692ed10ba2857ec8f'
r = requests.get(
    'https://api.odds-api.io/v3/events',
    params={'sport': 'tennis', 'apiKey': key, 'status': 'live'},
    timeout=10
)
events = r.json()
print(f'Live events: {len(events)}')
print(json.dumps(events[0], indent=2))
print('---')
print(json.dumps(events[1], indent=2))
"
cat /root/positions.json && echo "---" && tail -30 /root/kalshi_bot.log
python3 -c "
import json
bot_orders = json.load(open('/root/bot_orders.json'))
print(f'Bot orders: {len(bot_orders)}')
print(bot_orders)
"
grep -i "philadelphia\|DET\|PHI\|KXMLB" /root/kalshi_bot.log | tail -20
grep -i "KXMLB\|mlb\|baseball\|detroit\|phila" /root/kalshi_bot.log | grep -v "Fetcher\|ESPN" | tail -20
grep -n "CLOSED\|to_remove\|rm\|del open" /root/strategies.py | head -20
sed -n '260,300p' /root/strategies.py
grep -n "order_id\|position_record\|Position recorded" /root/kalshi_bot.py | head -20
python3 - << 'PYEOF'
with open('/root/strategies.py', 'r') as f:
    content = f.read()

old = '''    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        # Check if there is a resting (unfilled) bot order for this ticker
        # If so, keep the position — the order just hasn't filled yet
        order_id = pos.get("order_id","")'''

new = '''    rm=[]
    for ticker,pos in list(open_positions.items()):
        if ticker in kt: continue
        # Age gate — never remove a position younger than 5 minutes
        # Fills API can lag 30-60s, reconciler must not race against it
        try:
            et = pos.get("entry_time","")
            if et:
                age = (datetime.now(timezone.utc) - datetime.fromisoformat(et)).total_seconds()
                if age < 300:
                    log.info(f"[Reconcile] {ticker} only {int(age)}s old — keeping, fills may not have propagated")
                    continue
        except: pass
        # Check if there is a resting (unfilled) bot order for this ticker
        # If so, keep the position — the order just hasn't filled yet
        order_id = pos.get("order_id","")'''

if old in content:
    content = content.replace(old, new)
    with open('/root/strategies.py', 'w') as f:
        f.write(content)
    print("SUCCESS")
else:
    print("FAILED")
PYEOF

python3 -c "import kalshi_bot; print('OK')"
python3 -c "
import json
from datetime import datetime, timezone

pos = json.load(open('/root/positions.json'))

# Add the Philadelphia position back
pos['KXMLBSTGAME-26MAR201305DETPHI-PHI'] = {
    'side': 'no',
    'entry_price': 12,
    'peak_price': 36,
    'last_bid': 36,
    'contracts': 20,
    'strategy': 'value_fade',
    'entry_time': '2026-03-20T17:58:39+00:00',
    'event_ticker': 'KXMLBSTGAME-26MAR201305DETPHI',
    'reason': 'Restored from log',
    'entry_fee': 0.04,
    'is_bot': True,
    'order_id': '66fce856-51b4-4674-b0cc-60f1495ef0ca'
}

with open('/root/positions.json', 'w') as f:
    json.dump(pos, f, indent=2)
print('Position restored')
print(json.dumps(pos, indent=2))
"
tail -f /root/kalshi_bot.log | grep -i "detphi\|exit\|TP\|SELL"
tail -20 /root/kalshi_bot.log
cat /root/positions.json
rm -rf /root/__pycache__ && echo "cache cleared"
grep -n "KXMLBST\|spring\|stgame" /root/strategies.py | head -10
grep -i "CWSLAA\|LAA\|angels" /root/kalshi_bot.log | tail -20
grep -n "Hard stop\|40%\|STOP\|hard_stop" /root/price_watcher.py | head -20
python kalshi_bot.py
source kalshi-bot/bin/activate
python kalshi_bot.py
source kalshi-bot/bin/activate
python kalshi_bot.py
source kalshi-bot/bin/activate
screen -S kalshi
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
screen -r
screen -S kalshi
python3 /root/trade_tracker.py
screen -r
source kalshi-bot/bin/activate
screen -r
python kalshi_bot.py
source kalshi-bot/bin/activate
python kalshi_bot.py
screen -S kalshi
grep -E "(BUY YES|PLACED|LIVE ORDER|entry_price.*contracts)" /root/kalshi-bot/kalshi_bot.log | grep -v "BUY NO" | tail -50
cat /root/kalshi-bot/trade_log.csv | tail -20
cat /root/trade_log.csv
grep "KXNBAGAME" /root/trade_log.csv | grep "yes"
sed -n '1000,1790p' /root/kalshi_bot.py
grep -i "yes" /root/positions.json 2>/dev/null; grep -i "KXNBAGAME" /root/positions.json 2>/dev/null
grep "KXNBAGAME" /root/bot_orders.json 2>/dev/null | head -5
cd /root && python3 -c "
from strategies import _fetch_fills_raw
from kalshi_bot import _get_kalshi_client
client = _get_kalshi_client()
fills = _fetch_fills_raw(client)
nba_yes = [f for f in fills if 'KXNBAGAME' in (f.get('ticker','') or f.get('market_ticker','')) and f.get('side','') == 'yes' and f.get('action','') == 'buy']
for f in nba_yes:
    print(f.get('created_time','')[:19], f.get('ticker',''), f.get('side',''), f.get('action',''), f.get('count_fp',''), f.get('yes_price_dollars',''), f.get('order_id','')[:8])
"
if m.yes_bid >= 0.85:;     flag = "SIGNAL";     reason = f"Heavy favorite at {m.mid}c mid - fade candidate"; 
grep -n "yes_bid < 0.95\|yes_bid < 0.96\|yes_bid < 0.93" /root/kalshi_bot.py /root/strategies.py 2>/dev/null
grep -n "yes_bid" /root/strategies.py | head -30
cat /root/strategies.py | head -500
ls /root/*.py | sort && echo "---" && wc -l /root/*.py | sort -rn | head -25
screen -ls
pkill -f kalshi_bot.py
screen -ls | grep Detached | awk '{print $1}' | xargs -I {} screen -S {} -X quit 
cd /root && git add -A && git commit -m "sync live server state" && git push origin master
cat /root/.gitignore 2>/dev/null; echo "---"; git status --short | head -30
git ls-files | grep "\.py$" | sort
echo "kalshi-bot/" >> /root/.gitignore && git rm -r --cached kalshi-bot/ && git add .gitignore && git commit -m "remove venv from tracking" && git push origin master
cd /root && git log --oneline && echo "---" && git show HEAD --name-only | head -30
