"""Hysteresis used after the existing five-prediction smoothing window."""
class SirenDecision:
    def __init__(self, threshold=0.97, on_count=3, off_count=3):
        self.threshold, self.on_count, self.off_count = threshold, on_count, off_count
        self.reset()

    def reset(self):
        self.active = False
        self.high = self.low = 0

    def update(self, siren_probability):
        if siren_probability >= self.threshold:
            self.high += 1
            self.low = 0
            if self.high >= self.on_count:
                self.active = True
        else:
            self.low += 1
            self.high = 0
            if self.low >= self.off_count:
                self.active = False
        # Never bypass hysteresis via argmax when siren is not yet active.
        return "siren" if self.active else "other"
