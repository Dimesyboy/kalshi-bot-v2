import time
import math

class ExitManager:
    """Fixed-cent exits as verified in the audit (TP=+12c gross / +10c net, SL=-6c gross / -8c net).
    90-minute hard time exit. Side-aware for YES/NO. Uses your exact position dict + fee math.
    This replaces the old percentage logic for NBA/MLB (tennis stays untouched in next step).
    """
    TP_GROSS_CENTS = 12
    SL_GROSS_CENTS = 6
    MAX_HOLD_MINUTES = 90
    FEE_MULTIPLIER = 0.0175  # maker fee from your empirical measurement

    def should_exit(self, pos: dict, current_bid: int, current_time: float = None) -> tuple:
        """
        Returns: (should_exit: bool, reason: str, exit_bid: int)
        pos keys used: 'entry_price' (cents), 'side' ('yes'/'no'), 'entry_time', 'contracts'
        current_bid in cents (exactly as your _check_positions already uses)
        """
        if current_time is None:
            current_time = time.time()

        entry = pos.get("entry_price", 0)
        side = pos.get("side", "yes").lower()
        contracts = pos.get("contracts", 1)
        entry_time = pos.get("entry_time", current_time)  # fallback if not set yet

        if entry == 0 or contracts == 0:
            return False, "", current_bid

        # ── 90-minute hard time exit (audit priority) ──
        hold_minutes = (current_time - entry_time) / 60.0
        if hold_minutes >= self.MAX_HOLD_MINUTES:
            return True, f"TIME exit: held {hold_minutes:.0f} min", current_bid

        # ── Gross P&L in cents per contract (YES = price up, NO = price down) ──
        if side == "yes":
            gross_cents = current_bid - entry
        else:
            gross_cents = entry - current_bid

        # ── Fixed-cent TP/SL (exactly the verified math) ──
        if gross_cents >= self.TP_GROSS_CENTS:
            return True, f"TP hit: +{gross_cents}c gross", current_bid

        if gross_cents <= -self.SL_GROSS_CENTS:
            return True, f"SL hit: -{abs(gross_cents)}c gross", current_bid

        return False, "", current_bid

    def calculate_net_pnl(self, pos: dict, exit_bid: int) -> float:
        """Matches your fee verification (used for logging/telegram)"""
        entry = pos["entry_price"]
        side = pos["side"].lower()
        contracts = pos["contracts"]
        gross_cents = (exit_bid - entry) if side == "yes" else (entry - exit_bid)
        gross_usd = gross_cents * contracts / 100.0
        entry_fee = pos.get("entry_fee", 0.0)
        exit_fee = math.ceil(self.FEE_MULTIPLIER * contracts *
                             (exit_bid / 100) * (1 - exit_bid / 100) * 100) / 100
        return gross_usd - entry_fee - exit_fee
