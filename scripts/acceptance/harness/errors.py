"""Harness errors. Messages are stable prefixes for fixture matching."""


class HarnessError(Exception):
    """Fail-closed acceptance harness error. Never include credentials or bodies."""


class SchemaError(HarnessError):
    pass


class ReceiptError(HarnessError):
    pass


class HandoffError(HarnessError):
    pass


class CleanupError(HarnessError):
    pass


class PreflightError(HarnessError):
    pass


class DriverError(HarnessError):
    pass
