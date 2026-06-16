/// Test brokerage account schema and affordability checks for V1.1.S4.
///
/// BrokerageAccount: account id, cash, buying power, currency, holdings,
/// open orders, day notional used, and month notional used (T1).
///
/// fixtures: five deterministic test accounts — cash_rich, low_cash,
/// technology_heavy, diversified, and restricted_account (T2).
///
/// checkAffordability(): derives cash available, buying power, remaining daily
/// notional, remaining monthly notional, and max affordable basket size, then
/// returns an AffordabilityResult with outcome and all computed limits (T3).
const std = @import("std");
const basket = @import("basket.zig");

pub const portfolio_schema_version: u16 = 1;

// ---------------------------------------------------------------------------
// Capacity constants
// ---------------------------------------------------------------------------

/// Maximum concurrent holdings per account snapshot.
pub const max_holdings: usize = 32;
/// Maximum concurrent open orders per account snapshot.
pub const max_snapshot_open_orders: usize = 16;
/// Maximum bytes in a ticker symbol.
pub const max_ticker_len: usize = 8;

// ---------------------------------------------------------------------------
// Scale constants
// ---------------------------------------------------------------------------

pub const cents_per_dollar: i64 = 100;

// ---------------------------------------------------------------------------
// Types (T1)
// ---------------------------------------------------------------------------

pub const Currency = enum(u8) { usd };

pub const Side = enum(u8) { buy, sell };

/// A single open equity or ETF position held in the account.
pub const Holding = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    /// Latest mark-to-market value in cents.
    market_value_cents: i64,

    pub fn tickerSlice(self: *const Holding) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

/// A pending order that commits buying power until filled or cancelled.
pub const OpenOrder = struct {
    ticker: [max_ticker_len]u8,
    ticker_len: u8,
    side: Side,
    /// Committed notional in cents.
    notional_cents: i64,

    pub fn tickerSlice(self: *const OpenOrder) []const u8 {
        return self.ticker[0..self.ticker_len];
    }
};

/// Test brokerage account snapshot (T1).
///
/// buying_power_cents is already net of open-order commitments and any pending
/// settlement holds as reported by the test account provider.  It is the
/// binding limit for a new paper or sandbox order.  cash_cents is the raw
/// balance before deductions; it may be higher than buying_power_cents when
/// open orders have committed part of the balance.
///
/// max_open_order_count: maximum concurrent open orders the account allows.
/// When 0, no slot check is performed.
pub const BrokerageAccount = struct {
    account_id: u32,
    currency: Currency,
    /// Raw cash balance in cents.
    cash_cents: i64,
    /// Net buying power in cents; binding limit for new orders.
    buying_power_cents: i64,
    holdings: [max_holdings]Holding,
    holding_count: u8,
    open_orders: [max_snapshot_open_orders]OpenOrder,
    open_order_count: u8,
    /// Hard cap on concurrent open orders; 0 means no slot check.
    max_open_order_count: u8,
    day_notional_used_cents: i64,
    day_notional_limit_cents: i64,
    month_notional_used_cents: i64,
    month_notional_limit_cents: i64,
};

// ---------------------------------------------------------------------------
// Affordability check (T3)
// ---------------------------------------------------------------------------

/// Outcome of checkAffordability.
pub const AffordabilityOutcome = enum(u8) {
    allow = 0,
    deny_open_order_limit = 1,
    deny_insufficient_buying_power = 2,
    deny_day_limit_exceeded = 3,
    deny_month_limit_exceeded = 4,
    deny_invalid_notional = 5,
};

/// Result of checkAffordability (T3).
///
/// max_affordable_cents is the minimum of cash_available_cents,
/// buying_power_cents, remaining_daily_notional_cents, and
/// remaining_monthly_notional_cents.
/// On deny, it is the maximum the account can afford right now.
pub const AffordabilityResult = struct {
    outcome: AffordabilityOutcome,
    requested_notional_cents: i64,
    /// Effective ceiling: min(cash_available, buying_power, remaining_daily, remaining_monthly).
    max_affordable_cents: i64,
    /// Cash available for a new order after clamping invalid negatives and
    /// respecting the reported buying-power ceiling.
    cash_available_cents: i64,
    /// account.buying_power_cents (net limit for a new order).
    buying_power_cents: i64,
    remaining_daily_notional_cents: i64,
    remaining_monthly_notional_cents: i64,
};

/// Audit record payload for an affordability check.
/// Emitted alongside the basket-construction audit record when the account
/// check is the binding gate on a proposed trade ticket.
pub const AffordabilityCheckPayload = struct {
    account_id: u32,
    requested_notional_cents: i64,
    outcome: AffordabilityOutcome,
    max_affordable_cents: i64,
};

pub const BasketAffordabilityError = error{
    AccountMismatch,
};

/// Check whether account can afford requested_notional_cents for a new order.
///
/// Check order:
///   0. requested notional must be positive
///   1. open-order slot: open_order_count < max_open_order_count
///      (skipped when max_open_order_count == 0)
///   2. cash available: cash_available_cents >= requested_notional_cents
///   3. buying power: buying_power_cents >= requested_notional_cents
///   4. remaining daily notional >= requested_notional_cents
///   5. remaining monthly notional >= requested_notional_cents
///
/// remaining_daily  = max(0, day_notional_limit_cents  - day_notional_used_cents)
/// remaining_monthly = max(0, month_notional_limit_cents - month_notional_used_cents)
/// cash_available  = min(max(0, cash_cents), max(0, buying_power_cents))
/// max_affordable  = min(cash_available, buying_power, remaining_daily, remaining_monthly)
pub fn checkAffordability(
    account: *const BrokerageAccount,
    requested_notional_cents: i64,
) AffordabilityResult {
    const raw_cash_available = @max(@as(i64, 0), account.cash_cents);
    const buying_power = @max(@as(i64, 0), account.buying_power_cents);
    const cash_available = @min(raw_cash_available, buying_power);
    const remaining_daily = @max(
        @as(i64, 0),
        account.day_notional_limit_cents - account.day_notional_used_cents,
    );
    const remaining_monthly = @max(
        @as(i64, 0),
        account.month_notional_limit_cents - account.month_notional_used_cents,
    );
    const max_affordable = @min(cash_available, @min(buying_power, @min(remaining_daily, remaining_monthly)));

    const outcome: AffordabilityOutcome = blk: {
        if (requested_notional_cents <= 0)
            break :blk .deny_invalid_notional;
        if (account.max_open_order_count > 0 and
            account.open_order_count >= account.max_open_order_count)
            break :blk .deny_open_order_limit;
        if (requested_notional_cents > cash_available)
            break :blk .deny_insufficient_buying_power;
        if (requested_notional_cents > buying_power)
            break :blk .deny_insufficient_buying_power;
        if (requested_notional_cents > remaining_daily)
            break :blk .deny_day_limit_exceeded;
        if (requested_notional_cents > remaining_monthly)
            break :blk .deny_month_limit_exceeded;
        break :blk .allow;
    };

    return .{
        .outcome = outcome,
        .requested_notional_cents = requested_notional_cents,
        .max_affordable_cents = max_affordable,
        .cash_available_cents = cash_available,
        .buying_power_cents = buying_power,
        .remaining_daily_notional_cents = remaining_daily,
        .remaining_monthly_notional_cents = remaining_monthly,
    };
}

/// Check affordability for a concrete basket and ensure the basket belongs to
/// the same test account fixture.
pub fn checkBasketAffordability(
    account: *const BrokerageAccount,
    proposed_basket: *const basket.Basket,
) BasketAffordabilityError!AffordabilityResult {
    if (account.account_id != proposed_basket.account_id)
        return error.AccountMismatch;

    const basket_notional = if (proposed_basket.total_allocated_cents > 0)
        proposed_basket.total_allocated_cents
    else
        proposed_basket.target_notional_cents;

    return checkAffordability(account, basket_notional);
}

