--!optimize 2
--!native
--!nocheck

-- FastME v2.9.5: v2.9.4 optimized parser + validated exponents, math edge cases and safe serialization.
-- Value = {mantissa, exponent}; normalize externally constructed values first.
-- Raw pair APIs return two numbers; they do not allocate result tables.
-- Arithmetic expects normalized inputs and finite integer decimal exponents.
-- Existing allocating APIs always return independent result tables.

local FastME = {}
export type Value = {number}

FastME.VERSION = "2.9.5"
FastME.BUILD = "math-validation-20261007"

local abs = math.abs
local floor = math.floor
local sqrt = math.sqrt
local log = math.log
local log10 = math.log10
local exp = math.exp
local sin = math.sin
local cos = math.cos
local tan = math.tan
local asin = math.asin
local acos = math.acos
local atan = math.atan
local min = math.min
local huge = math.huge

local tonumber = tonumber
local tostring = tostring
local strSub = string.sub
local strFormat = string.format
local strByte = string.byte
local strLower = string.lower
local strUpper = string.upper
local strMatch = string.match

local NAN = 0 / 0
local POS_INF = huge
local NEG_INF = -huge
local PI = math.pi
local E_NUMBER = math.exp(1)
local LN10 = 2.302585092994046
local LOG10_E = 0.4342944819032518
local LOG10_2 = 0.3010299956639812
local LOG2_10 = 3.321928094887362
local HALF_LOG_TWO_PI = 0.9189385332046727
local DEG_TO_RAD_M = 1.7453292519943295
local DEG_TO_RAD_E = -2
local RAD_TO_DEG_M = 5.729577951308232
local RAD_TO_DEG_E = 1
local SQRT_HALF = 0.7071067811865476
local CBRT10 = 2.154434690031884
local CBRT100 = 4.641588833612779

-- v2.9.2 logarithmic persistence codec.
-- New finite values use signed ln(1 + |x|), which is monotonic and avoids the
-- catastrophic precision loss of the legacy 1e18-offset layout.
local LB_LEGACY_NEG_BASE = 1e18
local LB_LEGACY_POS_BASE = 2e18
local LB_LEGACY_ZERO = 4e18
local LB_LEGACY_EXP_SCALE = 1e14
local LB_LEGACY_MAN_SCALE = 1e13
local LB_LEGACY_NEG_MIN = 9.5e17
local LB_LEGACY_NEG_MAX = 1.05e18
local LB_LEGACY_POS_MIN = 1.95e18
local LB_LEGACY_POS_MAX = 2.05e18

local function log1pPositive(x: number): number
	local u = 1 + x
	if u == 1 then return x end
	-- Correct cancellation at small x; large x needs no ratio correction.
	if x >= 0.5 then return log(u) end
	return log(u) * (x / (u - 1))
end

local function expm1Positive(x: number): number
	if x < 1e-4 then
		return x * (1 + x * (0.5 + x * (0.16666666666666666 + x * (0.041666666666666664 + x * (0.008333333333333333 + x * (0.001388888888888889 + x * (0.0001984126984126984)))))))
	end
	return exp(x) - 1
end

local function isLegacyLB(val: number): boolean
	return val == LB_LEGACY_ZERO
		or (val >= LB_LEGACY_NEG_MIN and val <= LB_LEGACY_NEG_MAX)
		or (val >= LB_LEGACY_POS_MIN and val <= LB_LEGACY_POS_MAX)
end

local function legacyLBDecode(val: number): number
	if val == LB_LEGACY_ZERO then return 0 end

	local negative = val < 1.5e18
	local payload = negative and (LB_LEGACY_NEG_BASE - val) or (val - LB_LEGACY_POS_BASE)
	local exponent = floor(payload / LB_LEGACY_EXP_SCALE)
	if exponent < -324 or exponent > 308 then return NAN end

	local manPart = payload - exponent * LB_LEGACY_EXP_SCALE
	if manPart < 0 or manPart >= LB_LEGACY_EXP_SCALE then return NAN end

	local man = 10 ^ (manPart / LB_LEGACY_MAN_SCALE)
	local result = man * (10 ^ exponent)
	return negative and -result or result
end

local POW10_POS = {
	10, 100, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9,
	1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17,
}

local POW10_NEG = {
	1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9,
	1e-10, 1e-11, 1e-12, 1e-13, 1e-14, 1e-15, 1e-16, 1e-17,
}

local POW10_SCALE = table.create(617)
for exponent = -308, 308 do POW10_SCALE[exponent + 309] = 10 ^ exponent end

local function isSpaceByte(c: number): boolean
	return c == 32 or (c >= 9 and c <= 13)
end

local function normalizeRaw(m: number, e: number): (number, number)
	if e ~= e or e == POS_INF or e == NEG_INF or e % 1 ~= 0 then return NAN, 0 end
	if m == 0 then return 0, 0 end
	if m ~= m then return NAN, 0 end
	if m == POS_INF or m == NEG_INF then return m, 0 end

	local a = abs(m)
	if a >= 1 and a < 10 then return m, e end
	if a >= 10 and a < 100 then return m * 0.1, e + 1 end
	if a >= 0.1 and a < 1 then return m * 10, e - 1 end
	if a < 1e-308 then
		m = m * 1e308
		e = e - 308
		a = abs(m)
	end

	local shift = floor(log10(a))
	if shift > 0 and shift <= 17 then
		m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then
		m = m * POW10_POS[-shift]
	else
		m = m / POW10_SCALE[shift + 309]
	end
	e = e + shift
	a = abs(m)
	if a >= 10 then return m * 0.1, e + 1 end
	if a < 1 then return m * 10, e - 1 end
	return m, e
end

local function fromNumberRaw(x: number): (number, number)
	if x == 0 then return 0, 0 end
	if x ~= x then return NAN, 0 end
	if x == POS_INF or x == NEG_INF then return x, 0 end

	local a = abs(x)
	if a >= 1 then
		if a < 10 then return x, 0 end
		if a < 100 then return x * 0.1, 1 end
		if a < 1e3 then return x * 1e-2, 2 end
		if a < 1e4 then return x * 1e-3, 3 end
		if a < 1e5 then return x * 1e-4, 4 end
		if a < 1e6 then return x * 1e-5, 5 end
		if a < 1e7 then return x * 1e-6, 6 end
	else
		if a >= 1e-1 then return x * 10, -1 end
		if a >= 1e-2 then return x * 1e2, -2 end
		if a >= 1e-3 then return x * 1e3, -3 end
		if a >= 1e-4 then return x * 1e4, -4 end
		if a >= 1e-5 then return x * 1e5, -5 end
		if a >= 1e-6 then return x * 1e6, -6 end
		if a >= 1e-7 then return x * 1e7, -7 end
		if a < 1e-308 then return normalizeRaw(x * 1e308, -308) end
	end

	local e = floor(log10(a))
	local m
	if e > 0 and e <= 17 then
		m = x * POW10_NEG[e]
	elseif e < 0 and e >= -17 then
		m = x * POW10_POS[-e]
	else
		m = x / POW10_SCALE[e + 309]
	end
	local ma = abs(m)
	if ma >= 10 then return m * 0.1, e + 1 end
	if ma < 1 then return m * 10, e - 1 end
	return m, e
end

local function positiveIntegerRaw(x: number): (number, number)
	if x < 10 then return x, 0 end
	if x < 100 then return x * 0.1, 1 end
	if x < 1e3 then return x * 0.01, 2 end
	if x < 1e4 then return x * 0.001, 3 end
	if x < 1e5 then return x * 0.0001, 4 end
	if x < 1e6 then return x * 0.00001, 5 end
	if x < 1e7 then return x * 0.000001, 6 end
	return fromNumberRaw(x)
end

local function boundedNumberRaw(x: number): (number, number)
	if x == 0 then return 0, 0 end
	if x ~= x then return NAN, 0 end
	local a = x < 0 and -x or x
	if a >= 1 then return x, 0 end
	if a >= 1e-1 then return x * 10, -1 end
	if a >= 1e-2 then return x * 100, -2 end
	if a >= 1e-3 then return x * 1e3, -3 end
	if a >= 1e-4 then return x * 1e4, -4 end
	if a >= 1e-5 then return x * 1e5, -5 end
	if a >= 1e-6 then return x * 1e6, -6 end
	if a >= 1e-7 then return x * 1e7, -7 end
	return fromNumberRaw(x)
end

local function toNumberRaw(m: number, e: number): number
	if e ~= e or e == POS_INF or e == NEG_INF or e % 1 ~= 0 then return NAN end
	if m == 0 then return 0 end
	if m ~= m then return NAN end
	if m == POS_INF or m == NEG_INF then return m end
	if e > 308 then return m > 0 and POS_INF or NEG_INF end
	if e < -324 then return m < 0 and -0.0 or 0.0 end
	if e == 0 then return m end
	if e > 0 and e <= 17 then return m * POW10_POS[e] end
	if e < 0 and e >= -17 then return m * POW10_NEG[-e] end
	if e < -308 then
		local extra = -e - 308
		return (m * 1e-308) * POW10_NEG[extra]
	end
	return m * (POW10_SCALE[e + 309] or (10 ^ e))
end

local function manualStringRaw(s: string): (number, number)
	local n = #s
	if n == 0 then return NAN, 0 end

	local i = 1
	while i <= n and isSpaceByte(strByte(s, i)) do i = i + 1 end
	if i > n then return NAN, 0 end

	local sign = 1
	local c = strByte(s, i)
	if c == 45 then
		sign = -1
		i = i + 1
	elseif c == 43 then
		i = i + 1
	end

	local digitIndex = 0
	local intDigits = 0
	local sawDot = false
	local sawDigit = false
	local firstIndex = 0
	local sig = 0
	local sigCount = 0
	local expMode = false
	local expSign = 1
	local expValue = 0
	local expDigits = 0
	local expSignAllowed = true
	local trailingSpace = false

	while i <= n do
		c = strByte(s, i)
		if isSpaceByte(c) then
			trailingSpace = true
			i = i + 1
		elseif trailingSpace then
			return NAN, 0
		elseif not expMode then
			if c >= 48 and c <= 57 then
				sawDigit = true
				digitIndex = digitIndex + 1
				if not sawDot then intDigits = intDigits + 1 end
				local d = c - 48
				if firstIndex == 0 then
					if d ~= 0 then
						firstIndex = digitIndex
						sig = d
						sigCount = 1
					end
				elseif sigCount < 17 then
					sig = sig * 10 + d
					sigCount = sigCount + 1
				end
				i = i + 1
			elseif c == 46 then
				if sawDot then return NAN, 0 end
				sawDot = true
				i = i + 1
			elseif c == 101 or c == 69 then
				if not sawDigit then return NAN, 0 end
				expMode = true
				i = i + 1
			else
				return NAN, 0
			end
		else
			if expSignAllowed and (c == 43 or c == 45) then
				if c == 45 then expSign = -1 end
				expSignAllowed = false
				i = i + 1
			elseif c >= 48 and c <= 57 then
				expSignAllowed = false
				expDigits = expDigits + 1
				expValue = expValue * 10 + (c - 48)
				i = i + 1
			else
				return NAN, 0
			end
		end
	end

	if not sawDigit then return NAN, 0 end
	if expMode and expDigits == 0 then return NAN, 0 end
	if expValue == POS_INF then return NAN, 0 end
	if firstIndex == 0 then return 0, 0 end

	local m = sig
	if sigCount > 1 then m = m / (10 ^ (sigCount - 1)) end
	m = m * sign
	local e = intDigits - firstIndex
	if expMode then e = e + expSign * expValue end
	return normalizeRaw(m, e)
end

local function finishScientificRaw(left: number, exponent: number): (number, number)
	if left == 0 then return 0, 0 end
	local a = abs(left)
	if a >= 1 and a < 10 then return left, exponent end
	if a >= 10 and a < 100 then return left * 0.1, exponent + 1 end
	if a >= 0.1 and a < 1 then return left * 10, exponent - 1 end
	local m, e = fromNumberRaw(left)
	return m, e + exponent
end

-- Fast canonical scientific grammar. Captures are validated in native string.match,
-- avoiding one string.byte call per mantissa/exponent digit. Normal decimal strings
-- still use Luau's optimized tonumber builtin without pattern matching.
-- Only canonical *normalized* inputs use this shortcut; all other syntaxes fall
-- back to the original parser to preserve public behavior.
local function scientificStringRaw(s: string): (number?, number)
	local mantissaText, exponentText = strMatch(s, "^([%+%-]?[1-9]%.?%d*)[eE]([%+%-]?%d+)$")
	if mantissaText == nil then return nil, 0 end
	local exponent = tonumber(exponentText)
	if exponent == nil or exponent == POS_INF or exponent == NEG_INF or abs(exponent) < 309 then return nil, 0 end
	local mantissa = tonumber(mantissaText)
	if mantissa == nil or (mantissa > -1 and mantissa < 1) or mantissa >= 10 or mantissa <= -10 then return nil, 0 end
	return mantissa, exponent
end

-- Optional parsedKnown/parsedX pair is used only by public fromString. It
-- eliminates the previous duplicate tonumber call for difficult short inputs.
local function fromStringRaw(s: string, parsedX: number?, parsedKnown: boolean?): (number, number)
	local n = #s
	-- The common 4- and 5-digit huge exponent spellings are recognized cheaply.
	-- Do not run a pattern matcher for every normal decimal input.
	if n >= 10 then
		local candidate = false
		local c = strByte(s, n - 4)
		if c == 101 or c == 69 then
			candidate = true
		elseif n >= 11 then
			c = strByte(s, n - 5)
			if c == 101 or c == 69 then
				candidate = true
			elseif n >= 12 then
				c = strByte(s, n - 6)
				candidate = c == 101 or c == 69
			end
		end
		if candidate then
			local m, e = scientificStringRaw(s)
			if m ~= nil then return m, e end
		end
	end

	local x = parsedX
	if not parsedKnown then x = tonumber(s) end
	if x ~= nil then
		if x ~= POS_INF and x ~= NEG_INF then
			if x >= 1e-308 or x <= -1e-308 then return fromNumberRaw(x) end
		end

		-- Handle canonical very large exponents even when the earlier positional
		-- hint did not apply (short strings, many exponent digits or leading zeros).
		if n >= 5 then
			local m, e = scientificStringRaw(s)
			if m ~= nil then return m, e end
		end

		-- The compatibility path handles noncanonical significands and whitespace,
		-- including nonzero numbers underflowed by tonumber to zero.
		local ePos
		local hasNonZeroMantissa = x ~= 0
		local scanIndex = 1
		while scanIndex <= n do
			local byte = strByte(s, scanIndex)
			if byte == 101 or byte == 69 then ePos = scanIndex; break end
			if not hasNonZeroMantissa and byte >= 49 and byte <= 57 then hasNonZeroMantissa = true end
			scanIndex = scanIndex + 1
		end
		if x == 0 and not hasNonZeroMantissa then return 0, 0 end
		if ePos then
			local left = tonumber(strSub(s, 1, ePos - 1))
			local exponent = tonumber(strSub(s, ePos + 1))
			if left ~= nil and exponent ~= nil and left ~= POS_INF and left ~= NEG_INF and exponent % 1 == 0 then
				return finishScientificRaw(left, exponent)
			end
		end
	end
	return manualStringRaw(s)
end

local function addRaw(am: number, ae: number, bm: number, be: number): (number, number)
	if am ~= am or bm ~= bm then return NAN, 0 end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then return NAN, 0 end
		return am, 0
	end
	if bm == POS_INF or bm == NEG_INF then return bm, 0 end
	if am == 0 then return bm, be end
	if bm == 0 then return am, ae end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then return am, ae end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then return 0, 0 end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then return m, ae end
	if m >= 10 or m <= -10 then return m * 0.1, ae + 1 end
	if m >= 0.1 or m <= -0.1 then return m * 10, ae - 1 end
	return normalizeRaw(m, ae)
end

local function subRaw(am: number, ae: number, bm: number, be: number): (number, number)
	bm = -bm
	if am ~= am or bm ~= bm then return NAN, 0 end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then return NAN, 0 end
		return am, 0
	end
	if bm == POS_INF or bm == NEG_INF then return bm, 0 end
	if am == 0 then return bm, be end
	if bm == 0 then return am, ae end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then return am, ae end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then return 0, 0 end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then return m, ae end
	if m >= 10 or m <= -10 then return m * 0.1, ae + 1 end
	if m >= 0.1 or m <= -0.1 then return m * 10, ae - 1 end
	return normalizeRaw(m, ae)
end

local function mulRaw(am: number, ae: number, bm: number, be: number): (number, number)
	local m = am * bm
	local magnitude = abs(m)
	-- IEEE multiplication resolves NaN, infinity and zero-times-infinity.
	if not (magnitude < POS_INF) then return m, 0 end
	if m == 0 then return 0, 0 end
	local e = ae + be
	if magnitude >= 10 then return m * 0.1, e + 1 end
	if magnitude < 1 then return m * 10, e - 1 end
	return m, e
end

local function divRaw(am: number, ae: number, bm: number, be: number): (number, number)
	if bm == 0 then
		if am == 0 or am ~= am then return NAN, 0 end
		return am > 0 and POS_INF or NEG_INF, 0
	end
	local m = am / bm
	local magnitude = abs(m)
	if not (magnitude < POS_INF) then return m, 0 end
	if m == 0 then return 0, 0 end
	local e = ae - be
	if magnitude < 1 then return m * 10, e - 1 end
	if magnitude >= 10 then return m * 0.1, e + 1 end
	return m, e
end

local function scaleRaw(m: number, e: number, x: number): (number, number)
	if m ~= m or x ~= x then return NAN, 0 end
	if m == 0 or x == 0 then
		if m == POS_INF or m == NEG_INF or x == POS_INF or x == NEG_INF then return NAN, 0 end
		return 0, 0
	end
	if m == POS_INF or m == NEG_INF then return m * (x > 0 and 1 or -1), 0 end
	if x == POS_INF or x == NEG_INF then return m * x, 0 end
	local ax = x < 0 and -x or x
	local am = m < 0 and -m or m
	if am >= 1 and am < 10 and ax >= 0.1 and ax < 10 then
		local r = m * x
		if r >= 10 or r <= -10 then return r * 0.1, e + 1 end
		if r > -1 and r < 1 then return r * 10, e - 1 end
		return r, e
	end
	local xm, xe = fromNumberRaw(x)
	return mulRaw(m, e, xm, xe)
end

local function divScalarRaw(m: number, e: number, x: number): (number, number)
	if m ~= m or x ~= x then return NAN, 0 end
	if x == 0 then
		if m == 0 then return NAN, 0 end
		return m > 0 and POS_INF or NEG_INF, 0
	end
	if m == 0 then return 0, 0 end
	if m == POS_INF or m == NEG_INF then
		if x == POS_INF or x == NEG_INF then return NAN, 0 end
		return m * (x > 0 and 1 or -1), 0
	end
	if x == POS_INF or x == NEG_INF then return 0, 0 end
	local ax = x < 0 and -x or x
	local am = m < 0 and -m or m
	if am >= 1 and am < 10 and ax >= 0.1 and ax < 10 then
		local r = m / x
		if r >= 10 or r <= -10 then return r * 0.1, e + 1 end
		if r > -1 and r < 1 then return r * 10, e - 1 end
		return r, e
	end
	local xm, xe = fromNumberRaw(x)
	return divRaw(m, e, xm, xe)
end

local function recipRaw(m: number, e: number): (number, number)
	if m ~= m then return NAN, 0 end
	if m == 0 then return POS_INF, 0 end
	if m == POS_INF or m == NEG_INF then return 0, 0 end
	local r = 1 / m
	if r > -1 and r < 1 then return r * 10, -e - 1 end
	return r, -e
end

local function squareRaw(m: number, e: number): (number, number)
	local r = m * m
	if not (r < POS_INF) then return r, 0 end
	if r == 0 then return 0, 0 end
	local re = e + e
	if r >= 10 then return r * 0.1, re + 1 end
	return r, re
end

local function sqrtRaw(m: number, e: number): (number, number)
	if m ~= m or m < 0 then return NAN, 0 end
	if m == 0 then return 0, 0 end
	if m == POS_INF then return POS_INF, 0 end
	if e % 2 ~= 0 then m = m * 10; e = e - 1 end
	return sqrt(m), e * 0.5
end

local function fromLog10Raw(x: number): (number, number)
	if x ~= x then return NAN, 0 end
	if x == POS_INF then return POS_INF, 0 end
	if x == NEG_INF then return 0, 0 end
	local e = floor(x)
	local m = 10 ^ (x - e)
	if m >= 10 then return m * 0.1, e + 1 end
	if m < 1 then return m * 10, e - 1 end
	return m, e
end

local function powIntRaw(m: number, e: number, n: number): (number, number)
	-- Binary64 cannot resolve integer parity above 2^53; reject unbounded exponents.
	if n ~= n or n == POS_INF or n == NEG_INF or n % 1 ~= 0 or abs(n) > 9007199254740991 then return NAN, 0 end
	if n == 0 then return 1, 0 end
	if n == 1 then return m, e end
	if m == 0 then return n < 0 and POS_INF or 0, 0 end
	if n < 0 then
		local rm, re = powIntRaw(m, e, -n)
		return recipRaw(rm, re)
	end
	if n == 2 then return squareRaw(m, e) end

	-- Normalized finite mantissas get straight-line power paths.
	-- This avoids repeated squareRaw/mulRaw helper calls for common exponents.
	local am = m < 0 and -m or m
	if am >= 1 and am < 10 and n >= 3 and n <= 10 then
		local m2 = m * m
		local r
		if n == 3 then
			r = m2 * m
		elseif n == 4 then
			r = m2 * m2
		elseif n == 5 then
			local m4 = m2 * m2
			r = m4 * m
		elseif n == 6 then
			local m4 = m2 * m2
			r = m4 * m2
		elseif n == 7 then
			local m4 = m2 * m2
			r = m4 * m2 * m
		elseif n == 8 then
			local m4 = m2 * m2
			r = m4 * m4
		elseif n == 9 then
			local m4 = m2 * m2
			local m8 = m4 * m4
			r = m8 * m
		else -- 10
			local m4 = m2 * m2
			local m8 = m4 * m4
			r = m8 * m2
		end

		local ar = r < 0 and -r or r
		local shift
		if ar >= 1e5 then
			if ar >= 1e8 then
				shift = ar >= 1e9 and 9 or 8
			elseif ar >= 1e7 then
				shift = 7
			elseif ar >= 1e6 then
				shift = 6
			else
				shift = 5
			end
		elseif ar >= 1e3 then
			shift = ar >= 1e4 and 4 or 3
		elseif ar >= 1e2 then
			shift = 2
		elseif ar >= 10 then
			shift = 1
		else
			shift = 0
		end

		local re = e * n + shift
		if shift == 0 then return r, re end
		return r * POW10_NEG[shift], re
	end

	-- Fallback keeps behavior for non-normalized raw values and larger powers.
	local rm, re = 1, 0
	local bm, be = m, e
	while n > 0 do
		if n % 2 == 1 then rm, re = mulRaw(rm, re, bm, be) end
		n = floor(n * 0.5)
		if n > 0 then bm, be = squareRaw(bm, be) end
	end
	return rm, re
end

local function powRaw(m: number, e: number, p: number): (number, number)
	if p ~= p then return NAN, 0 end
	if p == 0 then return 1, 0 end
	if p == POS_INF or p == NEG_INF then
		if m == 1 and e == 0 then return 1, 0 end
		if m == -1 and e == 0 then return NAN, 0 end
		if m ~= m then return NAN, 0 end
		local a = abs(m)
		if a == 0 then return p > 0 and 0 or POS_INF, 0 end
		local magnitude = (log10(a) + e) * (p > 0 and 1 or -1)
		if magnitude == 0 then return NAN, 0 end
		return magnitude > 0 and POS_INF or 0, 0
	end
	if p == 1 then return m, e end
	if p == 2 then return squareRaw(m, e) end
	if m == 0 then return p < 0 and POS_INF or 0, 0 end
	if p % 1 == 0 and abs(p) <= 64 then return powIntRaw(m, e, p) end
	if m < 0 then
		if p % 1 ~= 0 or abs(p) > 9007199254740991 then return NAN, 0 end
		local rm, re = powRaw(-m, e, p)
		if p % 2 ~= 0 then rm = -rm end
		return rm, re
	end
	return fromLog10Raw((log10(m) + e) * p)
end

local function compareRaw(am: number, ae: number, bm: number, be: number): number
	if am ~= am or bm ~= bm then return 0 end
	if am == bm and ae == be then return 0 end
	if am == POS_INF then return 1 end
	if bm == POS_INF then return -1 end
	if am == NEG_INF then return -1 end
	if bm == NEG_INF then return 1 end
	if am < 0 and bm >= 0 then return -1 end
	if am >= 0 and bm < 0 then return 1 end
	if am == 0 then return bm > 0 and -1 or 1 end
	if bm == 0 then return am > 0 and 1 or -1 end
	if am > 0 then
		if ae ~= be then return ae < be and -1 or 1 end
		return am < bm and -1 or 1
	end
	if ae ~= be then return ae < be and 1 or -1 end
	return am < bm and -1 or 1
end

local function compareAbsRaw(am: number, ae: number, bm: number, be: number): number
	am, bm = abs(am), abs(bm)
	if am ~= am or bm ~= bm then return 0 end
	if am == bm then
		if am == POS_INF or am == 0 or ae == be then return 0 end
	end
	if am == POS_INF then return 1 end
	if bm == POS_INF then return -1 end
	if am == 0 then return -1 end
	if bm == 0 then return 1 end
	if ae ~= be then return ae < be and -1 or 1 end
	return am < bm and -1 or 1
end

-- Construction / conversion
-- v2.5 direct-entry rule:
-- Public hot paths contain their own core logic instead of forwarding to another
-- FastME API function. Compound APIs may still use private *Raw helpers internally.
function FastME.new(m: number, e: number?): Value local rm, re = normalizeRaw(m, e or 0); return {rm, re} end
function FastME.raw(m: number, e: number): Value return {m, e} end
function FastME.zero() return {0, 0} end
function FastME.one() return {1, 0} end
function FastME.two() return {2, 0} end
function FastME.ten() return {1, 1} end
function FastME.pi() return {PI, 0} end
function FastME.e() return {E_NUMBER, 0} end
function FastME.clone(a: Value): Value return {a[1], a[2]} end
function FastME.unpack(a: Value): (number, number) return a[1], a[2] end
function FastME.fromNumber(x: number): Value
	if x == 0 then return {0, 0} end
	if x ~= x then return {NAN, 0} end
	if x == POS_INF or x == NEG_INF then return {x, 0} end

	local a = abs(x)
	if a >= 1 then
		if a < 10 then return {x, 0} end
		if a < 100 then return {x * 0.1, 1} end
		if a < 1e3 then return {x * 1e-2, 2} end
		if a < 1e4 then return {x * 1e-3, 3} end
		if a < 1e5 then return {x * 1e-4, 4} end
		if a < 1e6 then return {x * 1e-5, 5} end
		if a < 1e7 then return {x * 1e-6, 6} end
	else
		if a >= 1e-1 then return {x * 10, -1} end
		if a >= 1e-2 then return {x * 1e2, -2} end
		if a >= 1e-3 then return {x * 1e3, -3} end
		if a >= 1e-4 then return {x * 1e4, -4} end
		if a >= 1e-5 then return {x * 1e5, -5} end
		if a >= 1e-6 then return {x * 1e6, -6} end
		if a >= 1e-7 then return {x * 1e7, -7} end
		if a < 1e-308 then
			local m, e = x * 1e308, -308
			local ma = abs(m)
			if ma >= 1 and ma < 10 then return {m, e} end
			if ma >= 10 and ma < 100 then return {m * 0.1, e + 1} end
			if ma >= 0.1 and ma < 1 then return {m * 10, e - 1} end
			local shift = floor(log10(ma))
			if shift > 0 and shift <= 17 then
				m = m * POW10_NEG[shift]
			elseif shift < 0 and shift >= -17 then
				m = m * POW10_POS[-shift]
			else
				m = m / POW10_SCALE[shift + 309]
			end
			e = e + shift
			ma = abs(m)
			if ma >= 10 then return {m * 0.1, e + 1} end
			if ma < 1 then return {m * 10, e - 1} end
			return {m, e}
		end
	end

	local e = floor(log10(a))
	local m
	if e > 0 and e <= 17 then
		m = x * POW10_NEG[e]
	elseif e < 0 and e >= -17 then
		m = x * POW10_POS[-e]
	else
		m = x / POW10_SCALE[e + 309]
	end
	local ma = abs(m)
	if ma >= 10 then return {m * 0.1, e + 1} end
	if ma < 1 then return {m * 10, e - 1} end
	return {m, e}
end

function FastME.fromString(s: string): Value
	-- Ordinary values use one builtin conversion, without allocations beyond
	-- the returned {mantissa, exponent} pair. Difficult inputs reuse that parse.
	if #s <= 18 then
		local x = tonumber(s)
		if x ~= nil and x ~= POS_INF and x ~= NEG_INF then
			if x >= 1e-308 or x <= -1e-308 then
				local m, e = fromNumberRaw(x)
				return {m, e}
			end
		end
		local m, e = fromStringRaw(s, x, true)
		return {m, e}
	end
	local m, e = fromStringRaw(s)
	return {m, e}
end

-- Allocation-free conversion for repeated parsing into a reused value table.
function FastME.fromStringInto(out: Value, s: string): Value
	local m, e = fromStringRaw(s)
	out[1] = m
	out[2] = e
	return out
end

function FastME.toNumber(a: Value): number
	local m, e = a[1], a[2]
	if e ~= e or e == POS_INF or e == NEG_INF or e % 1 ~= 0 then return NAN end
	if m == 0 then return 0 end
	if m ~= m then return NAN end
	if m == POS_INF or m == NEG_INF then return m end
	if e > 308 then return m > 0 and POS_INF or NEG_INF end
	if e < -324 then return m < 0 and -0.0 or 0.0 end
	if e == 0 then return m end
	if e > 0 and e <= 17 then return m * POW10_POS[e] end
	if e < 0 and e >= -17 then return m * POW10_NEG[-e] end
	if e < -308 then
		local extra = -e - 308
		return (m * 1e-308) * POW10_NEG[extra]
	end
	return m * (POW10_SCALE[e + 309] or (10 ^ e))
end

function FastME.normalize(a: Value): Value
	local m, e = a[1], a[2]
	if e ~= e or e == POS_INF or e == NEG_INF or e % 1 ~= 0 then return {NAN, 0} end
	if m == 0 then return {0, 0} end
	if m ~= m then return {NAN, 0} end
	if m == POS_INF or m == NEG_INF then return {m, 0} end
	local av = abs(m)
	if av >= 1 and av < 10 then return {m, e} end
	if av >= 10 and av < 100 then return {m * 0.1, e + 1} end
	if av >= 0.1 and av < 1 then return {m * 10, e - 1} end
	if av < 1e-308 then
		m = m * 1e308
		e = e - 308
		av = abs(m)
	end
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then
		m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then
		m = m * POW10_POS[-shift]
	else
		m = m / POW10_SCALE[shift + 309]
	end
	e = e + shift
	av = abs(m)
	if av >= 10 then return {m * 0.1, e + 1} end
	if av < 1 then return {m * 10, e - 1} end
	return {m, e}
end

-- Arithmetic
function FastME.add(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then return {NAN, 0} end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then return {NAN, 0} end
		return {am, 0}
	end
	if bm == POS_INF or bm == NEG_INF then return {bm, 0} end
	if am == 0 then return {bm, be} end
	if bm == 0 then return {am, ae} end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then return {am, ae} end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then return {0, 0} end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then return {m, ae} end
	if m >= 10 or m <= -10 then return {m * 0.1, ae + 1} end
	if m >= 0.1 or m <= -0.1 then return {m * 10, ae - 1} end
	local av = abs(m)
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then m = m * POW10_POS[-shift]
	else m = m / POW10_SCALE[shift + 309] end
	ae = ae + shift
	av = abs(m)
	if av >= 10 then return {m * 0.1, ae + 1} end
	if av < 1 then return {m * 10, ae - 1} end
	return {m, ae}
end

function FastME.sub(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], -b[1], b[2]
	if am ~= am or bm ~= bm then return {NAN, 0} end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then return {NAN, 0} end
		return {am, 0}
	end
	if bm == POS_INF or bm == NEG_INF then return {bm, 0} end
	if am == 0 then return {bm, be} end
	if bm == 0 then return {am, ae} end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then return {am, ae} end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then return {0, 0} end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then return {m, ae} end
	if m >= 10 or m <= -10 then return {m * 0.1, ae + 1} end
	if m >= 0.1 or m <= -0.1 then return {m * 10, ae - 1} end
	local av = abs(m)
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then m = m * POW10_POS[-shift]
	else m = m / POW10_SCALE[shift + 309] end
	ae = ae + shift
	av = abs(m)
	if av >= 10 then return {m * 0.1, ae + 1} end
	if av < 1 then return {m * 10, ae - 1} end
	return {m, ae}
end

function FastME.mul(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	local m = am * bm
	local magnitude = abs(m)
	-- IEEE multiplication resolves NaN, infinity and zero-times-infinity.
	if not (magnitude < POS_INF) then return {m, 0} end
	if m == 0 then return {0, 0} end
	local e = ae + be
	if magnitude >= 10 then return {m * 0.1, e + 1} end
	if magnitude < 1 then return {m * 10, e - 1} end
	return {m, e}
end

function FastME.div(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if bm == 0 then
		if am == 0 or am ~= am then return {NAN, 0} end
		return {am > 0 and POS_INF or NEG_INF, 0}
	end
	local m = am / bm
	local magnitude = abs(m)
	if not (magnitude < POS_INF) then return {m, 0} end
	if m == 0 then return {0, 0} end
	local e = ae - be
	if magnitude < 1 then return {m * 10, e - 1} end
	if magnitude >= 10 then return {m * 0.1, e + 1} end
	return {m, e}
end

function FastME.recip(a: Value): Value
	local m, e = a[1], a[2]
	if m ~= m then return {NAN, 0} end
	if m == 0 then return {POS_INF, 0} end
	if m == POS_INF or m == NEG_INF then return {0, 0} end
	local r = 1 / m
	if r > -1 and r < 1 then return {r * 10, -e - 1} end
	return {r, -e}
end

function FastME.square(a: Value): Value
	local m, e = a[1], a[2]
	local r = m * m
	if not (r < POS_INF) then return {r, 0} end
	if r == 0 then return {0, 0} end
	local re = e + e
	if r >= 10 then return {r * 0.1, re + 1} end
	return {r, re}
end

function FastME.sqrt(a: Value): Value
	local m, e = a[1], a[2]
	if m ~= m or m < 0 then return {NAN, 0} end
	if m == 0 then return {0, 0} end
	if m == POS_INF then return {POS_INF, 0} end
	if e % 2 ~= 0 then m = m * 10; e = e - 1 end
	return {sqrt(m), e * 0.5}
end
function FastME.cube(a: Value): Value
	local m, e = a[1], a[2]
	if m ~= m then return {NAN, 0} end
	if m == 0 then return {0, 0} end
	if m == POS_INF then return {POS_INF, 0} end
	if m == NEG_INF then return {NEG_INF, 0} end
	local am = m < 0 and -m or m
	if am >= 1 and am < 10 then
		local r = m * m * m
		local ar = r < 0 and -r or r
		local re = e * 3
		if ar >= 100 then return {r * 0.01, re + 2} end
		if ar >= 10 then return {r * 0.1, re + 1} end
		return {r, re}
	end
	local rm, re = normalizeRaw(m * m * m, e * 3)
	return {rm, re}
end
function FastME.cbrt(a: Value): Value
	local m, e = a[1], a[2]
	if m == 0 then return {0, 0} end
	if m ~= m then return {NAN, 0} end
	if m == POS_INF or m == NEG_INF then return {m, 0} end
	local negative = m < 0
	if negative then m = -m end
	local q = floor(e / 3)
	local r = e - q * 3
	local rm = m ^ (1 / 3)
	if r == 1 then rm = rm * CBRT10 elseif r == 2 then rm = rm * CBRT100 end
	if rm >= 10 then rm = rm * 0.1; q = q + 1 end
	if negative then rm = -rm end
	return {rm, q}
end
function FastME.powInt(a: Value, n: number): Value local m, e = powIntRaw(a[1], a[2], n); return {m, e} end
function FastME.pow(a: Value, p: number): Value local m, e = powRaw(a[1], a[2], p); return {m, e} end
function FastME.nthRoot(a: Value, n: number): Value
	if n == 0 or n ~= n then return {NAN, 0} end
	local m, e = a[1], a[2]
	if n == 2 then
		if m ~= m or m < 0 then return {NAN, 0} end
		if m == 0 then return {0, 0} end
		if m == POS_INF then return {POS_INF, 0} end
		if e % 2 ~= 0 then m = m * 10; e = e - 1 end
		return {sqrt(m), e * 0.5}
	end
	if n == 3 then
		if m == 0 then return {0, 0} end
		if m ~= m then return {NAN, 0} end
		if m == POS_INF or m == NEG_INF then return {m, 0} end
		local negative = m < 0
		if negative then m = -m end
		local q = floor(e / 3)
		local r = e - q * 3
		local rm = m ^ (1 / 3)
		if r == 1 then rm = rm * CBRT10 elseif r == 2 then rm = rm * CBRT100 end
		if rm >= 10 then rm = rm * 0.1; q = q + 1 end
		if negative then rm = -rm end
		return {rm, q}
	end
	if m < 0 then
		if n % 1 ~= 0 or abs(n) % 2 ~= 1 then return {NAN, 0} end
		local rm, re = fromLog10Raw((log10(-m) + e) / n)
		return {-rm, re}
	end
	local rm, re = fromLog10Raw((log10(m) + e) / n)
	return {rm, re}
end
FastME.root = FastME.nthRoot

-- Scalar arithmetic
function FastME.addNumber(a: Value, x: number): Value local m, e = fromNumberRaw(x); m, e = addRaw(a[1], a[2], m, e); return {m, e} end
function FastME.subNumber(a: Value, x: number): Value local m, e = fromNumberRaw(x); m, e = subRaw(a[1], a[2], m, e); return {m, e} end
-- Dedicated scalar kernels avoid converting x into a temporary mantissa/exponent pair.
function FastME.mulNumber(a: Value, x: number): Value
	local m, e = a[1], a[2]
	if m ~= m or x ~= x then return {NAN, 0} end
	if m == 0 or x == 0 then
		if m == POS_INF or m == NEG_INF or x == POS_INF or x == NEG_INF then return {NAN, 0} end
		return {0, 0}
	end
	if m == POS_INF or m == NEG_INF then return {m * (x > 0 and 1 or -1), 0} end
	if x == POS_INF or x == NEG_INF then return {m * x, 0} end
	local ax = x < 0 and -x or x
	local am = m < 0 and -m or m
	if am >= 1 and am < 10 and ax >= 0.1 and ax < 10 then
		local r = m * x
		if r >= 10 or r <= -10 then return {r * 0.1, e + 1} end
		if r > -1 and r < 1 then return {r * 10, e - 1} end
		return {r, e}
	end
	local xm, xe = fromNumberRaw(x)
	local rm, re = mulRaw(m, e, xm, xe); return {rm, re}
end
function FastME.divNumber(a: Value, x: number): Value
	local m, e = a[1], a[2]
	if m ~= m or x ~= x then return {NAN, 0} end
	if x == 0 then
		if m == 0 then return {NAN, 0} end
		return {m > 0 and POS_INF or NEG_INF, 0}
	end
	if m == 0 then return {0, 0} end
	if m == POS_INF or m == NEG_INF then
		if x == POS_INF or x == NEG_INF then return {NAN, 0} end
		return {m * (x > 0 and 1 or -1), 0}
	end
	if x == POS_INF or x == NEG_INF then return {0, 0} end
	local ax = x < 0 and -x or x
	local am = m < 0 and -m or m
	if am >= 1 and am < 10 and ax >= 0.1 and ax < 10 then
		local r = m / x
		if r >= 10 or r <= -10 then return {r * 0.1, e + 1} end
		if r > -1 and r < 1 then return {r * 10, e - 1} end
		return {r, e}
	end
	local xm, xe = fromNumberRaw(x)
	local rm, re = divRaw(m, e, xm, xe); return {rm, re}
end
function FastME.scale10(a: Value, amount: number): Value
	local m, e = a[1], a[2]
	if amount ~= amount or amount == POS_INF or amount == NEG_INF or amount % 1 ~= 0 then return {NAN, 0} end
	if m == 0 then return {0, 0} end
	if m ~= m then return {NAN, 0} end
	if m == POS_INF or m == NEG_INF then return {m, 0} end
	local nextExponent = e + amount
	if nextExponent ~= nextExponent or nextExponent == POS_INF or nextExponent == NEG_INF or nextExponent % 1 ~= 0 then return {NAN, 0} end
	return {m, nextExponent}
end

-- Sort-preserving scalar codec used for compact persistent numeric values.
-- New codes are roughly in [-709.8, 709.8] for all finite IEEE-754 doubles.
function FastME.lbencode(val: number): number
	if val ~= val then return NAN end
	if val == POS_INF or val == NEG_INF then return val end
	if val == 0 then return val end

	local magnitude = val < 0 and -val or val
	local encoded = log1pPositive(magnitude)
	return val < 0 and -encoded or encoded
end

function FastME.lbdecode(val: number): number
	if val ~= val then return NAN end
	if val == POS_INF or val == NEG_INF then return val end
	if val == 0 then return val end
	if isLegacyLB(val) then return legacyLBDecode(val) end

	local magnitude = val < 0 and -val or val
	local decoded = expm1Positive(magnitude)
	return val < 0 and -decoded or decoded
end

-- Compatibility spelling for projects that used the older typo.
FastME.lbecode = FastME.lbencode

-- Preserve the greatest decoded value and migrate legacy codes on the next write.
function FastME.encodeData(val: number, oldData: number?): number
	if oldData ~= nil then
		local old = FastME.lbdecode(oldData)
		if old == old then
			if val ~= val or old >= val then
				if isLegacyLB(oldData) then return FastME.lbencode(old) end
				return oldData
			end
		end
	end
	return FastME.lbencode(val)
end

-- Comparison / predicates
function FastME.compare(a: Value, b: Value): number
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then return 0 end
	if am == bm and ae == be then return 0 end
	if am == POS_INF then return 1 end
	if bm == POS_INF then return -1 end
	if am == NEG_INF then return -1 end
	if bm == NEG_INF then return 1 end
	if am < 0 and bm >= 0 then return -1 end
	if am >= 0 and bm < 0 then return 1 end
	if am == 0 then return bm > 0 and -1 or 1 end
	if bm == 0 then return am > 0 and 1 or -1 end
	if am > 0 then
		if ae ~= be then return ae < be and -1 or 1 end
		return am < bm and -1 or 1
	end
	if ae ~= be then return ae < be and 1 or -1 end
	return am < bm and -1 or 1
end
function FastME.compareAbs(a: Value, b: Value): number return compareAbsRaw(a[1], a[2], b[1], b[2]) end
function FastME.eq(a: Value, b: Value): boolean return a[1] == b[1] and a[2] == b[2] end
function FastME.neq(a: Value, b: Value): boolean return a[1] ~= b[1] or a[2] ~= b[2] end
function FastME.lt(a: Value, b: Value): boolean
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then return (0) < 0 end
	if am == bm and ae == be then return (0) < 0 end
	if am == POS_INF then return (1) < 0 end
	if bm == POS_INF then return (-1) < 0 end
	if am == NEG_INF then return (-1) < 0 end
	if bm == NEG_INF then return (1) < 0 end
	if am < 0 and bm >= 0 then return (-1) < 0 end
	if am >= 0 and bm < 0 then return (1) < 0 end
	if am == 0 then return (bm > 0 and -1 or 1) < 0 end
	if bm == 0 then return (am > 0 and 1 or -1) < 0 end
	if am > 0 then
		if ae ~= be then return (ae < be and -1 or 1) < 0 end
		return (am < bm and -1 or 1) < 0
	end
	if ae ~= be then return (ae < be and 1 or -1) < 0 end
	return (am < bm and -1 or 1) < 0
end
function FastME.lte(a: Value, b: Value): boolean
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then return false end
	if am == bm and ae == be then return (0) <= 0 end
	if am == POS_INF then return (1) <= 0 end
	if bm == POS_INF then return (-1) <= 0 end
	if am == NEG_INF then return (-1) <= 0 end
	if bm == NEG_INF then return (1) <= 0 end
	if am < 0 and bm >= 0 then return (-1) <= 0 end
	if am >= 0 and bm < 0 then return (1) <= 0 end
	if am == 0 then return (bm > 0 and -1 or 1) <= 0 end
	if bm == 0 then return (am > 0 and 1 or -1) <= 0 end
	if am > 0 then
		if ae ~= be then return (ae < be and -1 or 1) <= 0 end
		return (am < bm and -1 or 1) <= 0
	end
	if ae ~= be then return (ae < be and 1 or -1) <= 0 end
	return (am < bm and -1 or 1) <= 0
end
function FastME.gt(a: Value, b: Value): boolean
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then return (0) > 0 end
	if am == bm and ae == be then return (0) > 0 end
	if am == POS_INF then return (1) > 0 end
	if bm == POS_INF then return (-1) > 0 end
	if am == NEG_INF then return (-1) > 0 end
	if bm == NEG_INF then return (1) > 0 end
	if am < 0 and bm >= 0 then return (-1) > 0 end
	if am >= 0 and bm < 0 then return (1) > 0 end
	if am == 0 then return (bm > 0 and -1 or 1) > 0 end
	if bm == 0 then return (am > 0 and 1 or -1) > 0 end
	if am > 0 then
		if ae ~= be then return (ae < be and -1 or 1) > 0 end
		return (am < bm and -1 or 1) > 0
	end
	if ae ~= be then return (ae < be and 1 or -1) > 0 end
	return (am < bm and -1 or 1) > 0
end
function FastME.gte(a: Value, b: Value): boolean
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then return false end
	if am == bm and ae == be then return (0) >= 0 end
	if am == POS_INF then return (1) >= 0 end
	if bm == POS_INF then return (-1) >= 0 end
	if am == NEG_INF then return (-1) >= 0 end
	if bm == NEG_INF then return (1) >= 0 end
	if am < 0 and bm >= 0 then return (-1) >= 0 end
	if am >= 0 and bm < 0 then return (1) >= 0 end
	if am == 0 then return (bm > 0 and -1 or 1) >= 0 end
	if bm == 0 then return (am > 0 and 1 or -1) >= 0 end
	if am > 0 then
		if ae ~= be then return (ae < be and -1 or 1) >= 0 end
		return (am < bm and -1 or 1) >= 0
	end
	if ae ~= be then return (ae < be and 1 or -1) >= 0 end
	return (am < bm and -1 or 1) >= 0
end
function FastME.isZero(a: Value): boolean return a[1] == 0 end
function FastME.isOne(a: Value): boolean return a[1] == 1 and a[2] == 0 end
function FastME.isNaN(a: Value): boolean local e = a[2]; return a[1] ~= a[1] or e ~= e or e == POS_INF or e == NEG_INF or e % 1 ~= 0 end
function FastME.isInfinity(a: Value): boolean return a[1] == POS_INF or a[1] == NEG_INF end
function FastME.isFinite(a: Value): boolean local m, e = a[1], a[2]; return m == m and m ~= POS_INF and m ~= NEG_INF and e == e and e ~= POS_INF and e ~= NEG_INF and e % 1 == 0 end
function FastME.isPositive(a: Value): boolean return a[1] > 0 end
function FastME.isNegative(a: Value): boolean return a[1] < 0 end
function FastME.sign(a: Value): number return a[1] > 0 and 1 or (a[1] < 0 and -1 or 0) end
function FastME.abs(a: Value): Value return {abs(a[1]), a[2]} end
function FastME.neg(a: Value): Value return {-a[1], a[2]} end
function FastME.almostEqual(a: Value, b: Value, tolerance: number?): boolean
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am == bm and ae == be then return true end
	if ae == be and am == am and bm == bm and am ~= POS_INF and am ~= NEG_INF and bm ~= POS_INF and bm ~= NEG_INF then
		local d = am - bm
		if d < 0 then d = -d end
		local aa = am < 0 and -am or am
		local ab = bm < 0 and -bm or bm
		local scale = aa > ab and aa or ab
		if scale == 0 then return d == 0 end
		if tolerance == nil or tolerance == 1e-12 then return d <= scale * 1e-12 end
		if tolerance < 0 or tolerance ~= tolerance then return false end
		return d <= scale * tolerance
	end
	local dm, de = subRaw(am, ae, bm, be)
	dm = dm < 0 and -dm or dm
	local aam = am < 0 and -am or am
	local abm = bm < 0 and -bm or bm
	local sm, se
	if compareRaw(aam, ae, abm, be) >= 0 then sm, se = aam, ae else sm, se = abm, be end
	if sm == 0 then return dm == 0 end
	if tolerance == nil or tolerance == 1e-12 then
		return compareRaw(dm, de, sm, se - 12) <= 0
	end
	if tolerance < 0 or tolerance ~= tolerance then return false end
	local lm, le = scaleRaw(sm, se, tolerance)
	return compareRaw(dm, de, lm, le) <= 0
end

-- Min/max/clamp
function FastME.min(a: Value, b: Value): Value
	if a[1] ~= a[1] or b[1] ~= b[1] then return {NAN, 0} end
	return compareRaw(a[1], a[2], b[1], b[2]) <= 0 and {a[1], a[2]} or {b[1], b[2]}
end
function FastME.max(a: Value, b: Value): Value
	if a[1] ~= a[1] or b[1] ~= b[1] then return {NAN, 0} end
	return compareRaw(a[1], a[2], b[1], b[2]) >= 0 and {a[1], a[2]} or {b[1], b[2]}
end
function FastME.clamp(a: Value, lo: Value, hi: Value): Value
	if a[1] ~= a[1] or lo[1] ~= lo[1] or hi[1] ~= hi[1] then return {NAN, 0} end
	if compareRaw(a[1], a[2], lo[1], lo[2]) < 0 then return {lo[1], lo[2]} end
	if compareRaw(a[1], a[2], hi[1], hi[2]) > 0 then return {hi[1], hi[2]} end
	return {a[1], a[2]}
end

-- Logs / exponentials
function FastME.log10(a: Value): number if a[1] == 0 then return NEG_INF end; if a[1] < 0 then return NAN end; return log10(a[1]) + a[2] end
function FastME.ln(a: Value): number if a[1] == 0 then return NEG_INF end; if a[1] < 0 then return NAN end; return (log10(a[1]) + a[2]) * LN10 end
function FastME.log2(a: Value): number if a[1] == 0 then return NEG_INF end; if a[1] < 0 then return NAN end; return (log10(a[1]) + a[2]) * LOG2_10 end
function FastME.log(a: Value, base: number): number if base ~= base or base <= 0 or base == 1 or a[1] < 0 then return NAN end; if a[1] == 0 then return base > 1 and NEG_INF or POS_INF end; return (log10(a[1]) + a[2]) / log10(base) end
function FastME.fromLog10(x: number): Value
	if x ~= x then return {NAN, 0} end
	if x == POS_INF then return {POS_INF, 0} end
	if x == NEG_INF then return {0, 0} end
	local e = floor(x)
	local m = 10 ^ (x - e)
	if m >= 10 then return {m * 0.1, e + 1} end
	if m < 1 then return {m * 10, e - 1} end
	return {m, e}
end
function FastME.exp10(x: number): Value local m, e = fromLog10Raw(x); return {m, e} end
function FastME.exp2(x: number): Value local m, e = fromLog10Raw(x * LOG10_2); return {m, e} end
function FastME.exp(x: number): Value local m, e = fromLog10Raw(x * LOG10_E); return {m, e} end

-- Rounding
local function roundedIntegerRaw(m: number, e: number, mode: number): (number, number)
	if m == 0 then return 0, 0 end
	if m ~= m or m == POS_INF or m == NEG_INF then return m, e end
	if e < 0 then
		if mode == 1 then return m < 0 and -1 or 0, 0 end
		if mode == 2 then return m > 0 and 1 or 0, 0 end
		if mode == 3 and e == -1 then
			if m >= 5 then return 1, 0 end
			if m <= -5 then return -1, 0 end
		end
		return 0, 0
	end
	if e >= 15 then return m, e end
	local scale = e == 0 and 1 or POW10_POS[e]
	local x = m * scale
	if mode == 0 then x = x < 0 and -floor(-x) or floor(x)
	elseif mode == 1 then x = floor(x)
	elseif mode == 2 then x = -floor(-x)
	else x = x < 0 and -floor(-x + 0.5) or floor(x + 0.5) end
	if x == 0 then return 0, 0 end
	local r = x * (e == 0 and 1 or POW10_NEG[e])
	if r >= 10 or r <= -10 then return r * 0.1, e + 1 end
	if r > -1 and r < 1 then return normalizeRaw(r, e) end
	return r, e
end
function FastME.trunc(a: Value): Value local m,e=roundedIntegerRaw(a[1],a[2],0); return {m,e} end
function FastME.floor(a: Value): Value local m,e=roundedIntegerRaw(a[1],a[2],1); return {m,e} end
function FastME.ceil(a: Value): Value local m,e=roundedIntegerRaw(a[1],a[2],2); return {m,e} end
function FastME.round(a: Value): Value local m,e=roundedIntegerRaw(a[1],a[2],3); return {m,e} end
function FastME.frac(a: Value): Value
	local m, e = a[1], a[2]
	if m == 0 then return {0, 0} end
	if m ~= m or m == POS_INF or m == NEG_INF then return {NAN, 0} end
	if e < 0 then return {m, e} end
	if e >= 15 then return {0, 0} end
	local scale = e == 0 and 1 or POW10_POS[e]
	local x = m * scale
	x = x < 0 and -floor(-x) or floor(x)
	local fm = m - x * (e == 0 and 1 or POW10_NEG[e])
	if fm == 0 then return {0, 0} end
	local fe = e
	local af = fm < 0 and -fm or fm
	if af >= 1 and af < 10 then return {fm, fe} end
	if af >= 0.1 then return {fm * 10, fe - 1} end
	local rm, re = normalizeRaw(fm, fe)
	return {rm, re}
end
function FastME.roundSignificant(a: Value, digits: number?): Value
	digits = floor(digits or 6)
	if digits < 1 then return {0, 0} end
	if digits > 17 then digits = 17 end
	if a[1] == 0 or a[1] ~= a[1] or a[1] == POS_INF or a[1] == NEG_INF then return {a[1], a[2]} end
	local scale = digits == 1 and 1 or POW10_POS[digits - 1]
	local v = floor(abs(a[1]) * scale + 0.5) / scale
	if a[1] < 0 then v = -v end
	local m, e = normalizeRaw(v, a[2]); return {m, e}
end

-- Distance / interpolation
function FastME.distance(a: Value, b: Value): Value
	local m, e = subRaw(a[1], a[2], b[1], b[2]); return {abs(m), e}
end
FastME.absDelta = FastME.distance
function FastME.lerp(a: Value, b: Value, t: number): Value
	if t == 0 then return {a[1], a[2]} end
	if t == 1 then return {b[1], b[2]} end
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am == am and bm == bm and am ~= POS_INF and am ~= NEG_INF and bm ~= POS_INF and bm ~= NEG_INF and t == t and t ~= POS_INF and t ~= NEG_INF then
		local d = ae - be
		if d >= -17 and d <= 17 then
			local x, y, e
			if d >= 0 then x, y, e = am, bm * (d == 0 and 1 or POW10_NEG[d]), ae
			else d = -d; x, y, e = am * POW10_NEG[d], bm, be end
			local r = x + (y - x) * t
			if r == 0 or r >= 0.1 or r <= -0.1 then
				local m,re = normalizeRaw(r, e); return {m,re}
			end
		end
	end
	local dm, de = subRaw(bm, be, am, ae)
	dm, de = scaleRaw(dm, de, t)
	local m, e = addRaw(am, ae, dm, de); return {m, e}
end
function FastME.inverseLerp(a: Value, b: Value, value: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	local vm, ve = value[1], value[2]
	if am == am and bm == bm and vm == vm
		and am ~= POS_INF and am ~= NEG_INF and bm ~= POS_INF and bm ~= NEG_INF and vm ~= POS_INF and vm ~= NEG_INF then
		local e = ae
		if be > e then e = be end
		if ve > e then e = ve end
		local da, db, dv = e - ae, e - be, e - ve
		if da <= 17 and db <= 17 and dv <= 17 then
			local ax = am * (da == 0 and 1 or POW10_NEG[da])
			local bx = bm * (db == 0 and 1 or POW10_NEG[db])
			local vx = vm * (dv == 0 and 1 or POW10_NEG[dv])
			local den = bx - ax
			if den ~= 0 then
				local m,re = fromNumberRaw((vx - ax) / den); return {m,re}
			end
		end
	end
	local nm, ne = subRaw(vm, ve, am, ae)
	local dm, de = subRaw(bm, be, am, ae)
	local m, e = divRaw(nm, ne, dm, de); return {m, e}
end
function FastME.remap(value: Value, oldMin: Value, oldMax: Value, newMin: Value, newMax: Value): Value
	local vm, ve = value[1], value[2]
	local omin, oe = oldMin[1], oldMin[2]
	local omax, oxe = oldMax[1], oldMax[2]
	local nmin, ne = newMin[1], newMin[2]
	local nmax, nxe = newMax[1], newMax[2]
	if vm == vm and omin == omin and omax == omax and nmin == nmin and nmax == nmax
		and vm ~= POS_INF and vm ~= NEG_INF and omin ~= POS_INF and omin ~= NEG_INF
		and omax ~= POS_INF and omax ~= NEG_INF and nmin ~= POS_INF and nmin ~= NEG_INF and nmax ~= POS_INF and nmax ~= NEG_INF then
		local oeMax = oe
		if oxe > oeMax then oeMax = oxe end
		if ve > oeMax then oeMax = ve end
		local dv, d0, d1 = oeMax - ve, oeMax - oe, oeMax - oxe
		if dv <= 17 and d0 <= 17 and d1 <= 17 then
			local vx = vm * (dv == 0 and 1 or POW10_NEG[dv])
			local x0 = omin * (d0 == 0 and 1 or POW10_NEG[d0])
			local x1 = omax * (d1 == 0 and 1 or POW10_NEG[d1])
			local den = x1 - x0
			if den ~= 0 then
				local t = (vx - x0) / den
				local neMax = ne > nxe and ne or nxe
				local nd0, nd1 = neMax - ne, neMax - nxe
				if nd0 <= 17 and nd1 <= 17 then
					local y0 = nmin * (nd0 == 0 and 1 or POW10_NEG[nd0])
					local y1 = nmax * (nd1 == 0 and 1 or POW10_NEG[nd1])
					local r = y0 + (y1 - y0) * t
					if r == 0 or r >= 0.1 or r <= -0.1 then
						local m,re = normalizeRaw(r, neMax); return {m,re}
					end
				end
			end
		end
	end
	local nm, nme = subRaw(vm, ve, omin, oe)
	local qm, qe = subRaw(omax, oxe, omin, oe)
	local tm, te = divRaw(nm, nme, qm, qe)
	local dm, de = subRaw(nmax, nxe, nmin, ne)
	local sm, se = mulRaw(dm, de, tm, te)
	local m, e = addRaw(nmin, ne, sm, se); return {m, e}
end
function FastME.smoothstep(edge0: Value, edge1: Value, value: Value): Value
	local em0, ee0, em1, ee1, vm, ve = edge0[1], edge0[2], edge1[1], edge1[2], value[1], value[2]
	if em0 == em0 and em1 == em1 and vm == vm
		and em0 ~= POS_INF and em0 ~= NEG_INF and em1 ~= POS_INF and em1 ~= NEG_INF and vm ~= POS_INF and vm ~= NEG_INF then
		local e = ee0
		if ee1 > e then e = ee1 end
		if ve > e then e = ve end
		local d0, d1, dv = e - ee0, e - ee1, e - ve
		if d0 <= 17 and d1 <= 17 and dv <= 17 then
			local x0 = em0 * (d0 == 0 and 1 or POW10_NEG[d0])
			local x1 = em1 * (d1 == 0 and 1 or POW10_NEG[d1])
			local den = x1 - x0
			if den ~= 0 then
				local t = (vm * (dv == 0 and 1 or POW10_NEG[dv]) - x0) / den
				if t < 0 then t = 0 elseif t > 1 then t = 1 end
				local m,re = boundedNumberRaw(t * t * (3 - 2 * t)); return {m,re}
			end
		end
	end
	local nm, ne = subRaw(vm, ve, em0, ee0)
	local dm, de = subRaw(em1, ee1, em0, ee0)
	local tm, te = divRaw(nm, ne, dm, de)
	local t = toNumberRaw(tm, te)
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local m, e = boundedNumberRaw(t * t * (3 - 2 * t)); return {m, e}
end
function FastME.smootherstep(edge0: Value, edge1: Value, value: Value): Value
	local em0, ee0, em1, ee1, vm, ve = edge0[1], edge0[2], edge1[1], edge1[2], value[1], value[2]
	if em0 == em0 and em1 == em1 and vm == vm
		and em0 ~= POS_INF and em0 ~= NEG_INF and em1 ~= POS_INF and em1 ~= NEG_INF and vm ~= POS_INF and vm ~= NEG_INF then
		local e = ee0
		if ee1 > e then e = ee1 end
		if ve > e then e = ve end
		local d0, d1, dv = e - ee0, e - ee1, e - ve
		if d0 <= 17 and d1 <= 17 and dv <= 17 then
			local x0 = em0 * (d0 == 0 and 1 or POW10_NEG[d0])
			local x1 = em1 * (d1 == 0 and 1 or POW10_NEG[d1])
			local den = x1 - x0
			if den ~= 0 then
				local t = (vm * (dv == 0 and 1 or POW10_NEG[dv]) - x0) / den
				if t < 0 then t = 0 elseif t > 1 then t = 1 end
				local m,re = boundedNumberRaw(t * t * t * (t * (t * 6 - 15) + 10)); return {m,re}
			end
		end
	end
	local nm, ne = subRaw(vm, ve, em0, ee0)
	local dm, de = subRaw(em1, ee1, em0, ee0)
	local tm, te = divRaw(nm, ne, dm, de)
	local t = toNumberRaw(tm, te)
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local m, e = boundedNumberRaw(t * t * t * (t * (t * 6 - 15) + 10)); return {m, e}
end

-- Means / geometry
function FastME.mean(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am == am and bm == bm and am ~= POS_INF and am ~= NEG_INF and bm ~= POS_INF and bm ~= NEG_INF then
		local d = ae - be
		if d >= -17 and d <= 17 then
			local x,y,e
			if d >= 0 then x,y,e=am,bm*(d==0 and 1 or POW10_NEG[d]),ae
			else d=-d;x,y,e=am*POW10_NEG[d],bm,be end
			local r=(x+y)*0.5
			if r==0 or r>=0.1 or r<=-0.1 then local m,re=normalizeRaw(r,e); return {m,re} end
		end
	end
	local m, e = addRaw(am, ae, bm, be); m, e = scaleRaw(m, e, 0.5); return {m, e}
end
FastME.midpoint = FastME.mean
function FastME.geometricMean(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am < 0 or bm < 0 then return {NAN, 0} end
	local m, e = mulRaw(am, ae, bm, be)
	local rm, re = sqrtRaw(m, e); return {rm, re}
end
function FastME.harmonicMean(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am == 0 or bm == 0 then return {0, 0} end
	if am == am and bm == bm and am ~= POS_INF and am ~= NEG_INF and bm ~= POS_INF and bm ~= NEG_INF then
		local d=ae-be
		if d>=-17 and d<=17 then
			local x,y,e
			if d>=0 then x,y,e=am,bm*(d==0 and 1 or POW10_NEG[d]),ae
			else d=-d;x,y,e=am*POW10_NEG[d],bm,be end
			local den=x+y
			if den~=0 and (den>=1e-12 or den<=-1e-12) then local m,re=normalizeRaw((2*x*y)/den,e); return {m,re} end
		end
	end
	local nm, ne = mulRaw(am, ae, bm, be)
	nm, ne = mulRaw(nm, ne, 2, 0)
	local dm, de = addRaw(am, ae, bm, be)
	local m, e = divRaw(nm, ne, dm, de); return {m, e}
end
function FastME.rms(a: Value, b: Value): Value
	local am, ae = a[1], a[2]
	local bm, be = b[1], b[2]
	if am ~= am or bm ~= bm then return {NAN, 0} end
	if am == POS_INF or am == NEG_INF or bm == POS_INF or bm == NEG_INF then return {POS_INF, 0} end
	am = am < 0 and -am or am
	bm = bm < 0 and -bm or bm
	if am == 0 then local m,e=scaleRaw(bm, be, SQRT_HALF); return {m,e} end
	if bm == 0 then local m,e=scaleRaw(am, ae, SQRT_HALF); return {m,e} end
	if ae < be then am,bm,ae,be=bm,am,be,ae elseif ae == be and am < bm then am,bm=bm,am end
	local d = ae - be
	if d > 17 then local m,e=scaleRaw(am, ae, SQRT_HALF); return {m,e} end
	local y = bm * (d == 0 and 1 or POW10_NEG[d])
	local m,e = normalizeRaw(sqrt((am * am + y * y) * 0.5), ae)
	return {m,e}
end
function FastME.hypot(a: Value, b: Value): Value
	local am, ae = a[1], a[2]
	local bm, be = b[1], b[2]
	if am ~= am or bm ~= bm then return {NAN,0} end
	local aInf = am == POS_INF or am == NEG_INF
	local bInf = bm == POS_INF or bm == NEG_INF
	if aInf and bInf then return {NAN,0} end
	if aInf or bInf then return {POS_INF,0} end
	am = am < 0 and -am or am
	bm = bm < 0 and -bm or bm
	if am == 0 then return {bm, be} end
	if bm == 0 then return {am, ae} end
	if ae < be then am,bm,ae,be=bm,am,be,ae elseif ae == be and am < bm then am,bm=bm,am end
	local d = ae - be
	if d > 17 then return {am, ae} end
	local y = bm * (d == 0 and 1 or POW10_NEG[d])
	local m,e = normalizeRaw(sqrt(am * am + y * y), ae)
	return {m,e}
end

-- Percent / growth helpers
function FastME.percentOf(a: Value, percent: number): Value
	local m, e = scaleRaw(a[1], a[2], percent * 0.01); return {m, e}
end
function FastME.increasePercent(a: Value, percent: number): Value
	local m, e = scaleRaw(a[1], a[2], 1 + percent * 0.01); return {m, e}
end
function FastME.decreasePercent(a: Value, percent: number): Value
	local m, e = scaleRaw(a[1], a[2], 1 - percent * 0.01); return {m, e}
end
function FastME.percentChange(oldValue: Value, newValue: Value): number
	if oldValue[1] == 0 then return NAN end
	local dm, de = subRaw(newValue[1], newValue[2], oldValue[1], oldValue[2])
	local rm, re = divRaw(dm, de, oldValue[1], oldValue[2])
	return toNumberRaw(rm, re) * 100
end
function FastME.ordersBetween(a: Value, b: Value): number
	if a[1] <= 0 or b[1] <= 0 then return NAN end
	return (log10(b[1]) + b[2]) - (log10(a[1]) + a[2])
end

-- Modulo for a large decimal-exponent gap: do NOT construct the enormous quotient.
-- This rare/slow path uses base-10 modular exponentiation of 15-digit decimal
-- significands. Every intermediate integer stays below 2^53 (exact in f64).
-- The input format is still an approximate 15-16-digit mantissa/exponent pair;
-- this deliberately rounds each mantissa to 15 significant decimal digits.
local MOD_DECIMAL_SCALE = 1e14
local MAX_SAFE_INTEGER = 9007199254740991

local function modularMultiply(a: number, b: number, modulus: number): number
	-- Exact binary64 integer products while modulus <= floor(sqrt(2^53-1)).
	-- Particularly important for game remainder operations with small integer divisors.
	if modulus <= 94906265 then return (a * b) % modulus end
	local result = 0
	while b > 0 do
		if b % 2 == 1 then result = (result + a) % modulus end
		b = floor(b * 0.5)
		if b > 0 then a = (a + a) % modulus end
	end
	return result
end

local function modularPower10(exponent: number, modulus: number): number
	local value = 1 % modulus
	local base = 10 % modulus
	while exponent > 0 do
		if exponent % 2 == 1 then value = modularMultiply(value, base, modulus) end
		exponent = floor(exponent * 0.5)
		if exponent > 0 then base = modularMultiply(base, base, modulus) end
	end
	return value
end

local function wideRemainderRaw(am: number, ae: number, bm: number, be: number, euclidean: boolean): (number, number)
	local gap = ae - be
	if gap > MAX_SAFE_INTEGER then return NAN, 0 end
	-- Specialize small integer divisors: exact f64 modulo without a 15-digit
	-- scaled divisor, avoiding dozens of slow double-and-add iterations.
	if be >= 0 and be <= 7 and ae >= 14 then
		local divisor = abs(bm) * (be == 0 and 1 or POW10_POS[be])
		if divisor >= 1 and divisor <= 94906265 and divisor % 1 == 0 then
			local digits = floor(abs(am) * MOD_DECIMAL_SCALE + 0.5)
			local rem = modularMultiply(digits % divisor, modularPower10(ae - 14, divisor), divisor)
			if rem == 0 then return 0, 0 end
			if euclidean then
				if (am < 0) ~= (bm < 0) then rem = divisor - rem end
				if bm < 0 then rem = -rem end
			elseif am < 0 then
				rem = -rem
			end
			return normalizeRaw(rem, 0)
		end
	end
	local a = floor(abs(am) * MOD_DECIMAL_SCALE + 0.5)
	local b = floor(abs(bm) * MOD_DECIMAL_SCALE + 0.5)
	if b == 0 then return NAN, 0 end
	local rem = modularMultiply(a % b, modularPower10(gap, b), b)
	if rem == 0 then return 0, 0 end
	if euclidean then
		if (am < 0) ~= (bm < 0) then rem = b - rem end
		if bm < 0 then rem = -rem end
	elseif am < 0 then
		rem = -rem
	end
	return normalizeRaw(rem / MOD_DECIMAL_SCALE, be)
end

-- rem follows truncated quotient semantics; mod follows floor quotient semantics.
-- Common small exponents preserve the existing lightweight native fast path.
function FastME.rem(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm or bm == 0 then return {NAN, 0} end
	if am == POS_INF or am == NEG_INF then return {NAN, 0} end
	if bm == POS_INF or bm == NEG_INF then return {am, ae} end
	if am == 0 then return {0, 0} end
	local gap = ae - be
	if gap ~= gap or gap == POS_INF or gap == NEG_INF then return {NAN, 0} end
	if gap >= 13 then
		local m, e = wideRemainderRaw(am, ae, bm, be, false)
		return {m, e}
	end
	if gap < -17 then return {am, ae} end
	-- Fast exact-integer path: converting normalized pairs may differ by 1 ULP,
	-- causing a truncated floating quotient to miss exact multiples.
	if gap > 1 and ae >= 0 and ae <= 14 and be >= 0 and be <= 14 then
		local av = toNumberRaw(am, ae)
		local bv = toNumberRaw(bm, be)
		local aa = abs(av)
		local ba = abs(bv)
		if aa <= MAX_SAFE_INTEGER and ba <= MAX_SAFE_INTEGER and ba > 0 then
			local ai = aa >= 4503599627370496 and aa or floor(aa + 0.5)
			local bi = ba >= 4503599627370496 and ba or floor(ba + 0.5)
			if bi > 0 and abs(aa - ai) <= aa * 5e-16 and abs(ba - bi) <= ba * 5e-16 then
				local value = (am < 0 and -ai or ai) % (bm < 0 and -bi or bi)
				-- Luau % uses floor quotient; rem needs truncated quotient instead.
				if value ~= 0 and (am < 0) ~= (bm < 0) then
					value = value - (bm < 0 and -bi or bi)
				end
				local m, e = normalizeRaw(value, 0)
				return {m, e}
			end
		end
	end
	if gap > 1 then
		local qm = am / bm
		local qe = gap
		if qm > -1 and qm < 1 then qm = qm * 10; qe = qe - 1
		elseif qm >= 10 or qm <= -10 then qm = qm * 0.1; qe = qe + 1 end
		local q = qe == 0 and qm or qm * POW10_POS[qe]
		q = q < 0 and -floor(-q) or floor(q)
		local im, ie = fromNumberRaw(q)
		local pm, pe = mulRaw(bm, be, im, ie)
		local m, e = subRaw(am, ae, pm, pe)
		return {m, e}
	end
	local scale = gap == 0 and 1 or (gap > 0 and POW10_POS[gap] or POW10_NEG[-gap])
	local scaled = am * scale
	local q = scaled / bm
	q = q < 0 and -floor(-q) or floor(q)
	local m, e = normalizeRaw(scaled - q * bm, be)
	return {m, e}
end

function FastME.mod(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm or bm == 0 then return {NAN, 0} end
	if am == POS_INF or am == NEG_INF then return {NAN, 0} end
	if bm == POS_INF or bm == NEG_INF then return {NAN, 0} end
	if am == 0 then return {0, 0} end
	local gap = ae - be
	if gap ~= gap or gap == POS_INF or gap == NEG_INF then return {NAN, 0} end
	if gap >= 13 then
		local m, e = wideRemainderRaw(am, ae, bm, be, true)
		return {m, e}
	end
	if gap < -17 then
		if (am > 0) == (bm > 0) then return {am, ae} end
		local m, e = addRaw(am, ae, bm, be)
		return {m, e}
	end
	if gap > 1 and ae >= 0 and ae <= 14 and be >= 0 and be <= 14 then
		local av = toNumberRaw(am, ae)
		local bv = toNumberRaw(bm, be)
		local aa = abs(av)
		local ba = abs(bv)
		if aa <= MAX_SAFE_INTEGER and ba <= MAX_SAFE_INTEGER and ba > 0 then
			local ai = aa >= 4503599627370496 and aa or floor(aa + 0.5)
			local bi = ba >= 4503599627370496 and ba or floor(ba + 0.5)
			if bi > 0 and abs(aa - ai) <= aa * 5e-16 and abs(ba - bi) <= ba * 5e-16 then
				local value = (am < 0 and -ai or ai) % (bm < 0 and -bi or bi)
				local m, e = normalizeRaw(value, 0)
				return {m, e}
			end
		end
	end
	if gap > 1 then
		local qm = am / bm
		local qe = gap
		if qm > -1 and qm < 1 then qm = qm * 10; qe = qe - 1
		elseif qm >= 10 or qm <= -10 then qm = qm * 0.1; qe = qe + 1 end
		local q = qe == 0 and qm or qm * POW10_POS[qe]
		q = floor(q)
		local im, ie = fromNumberRaw(q)
		local pm, pe = mulRaw(bm, be, im, ie)
		local m, e = subRaw(am, ae, pm, pe)
		return {m, e}
	end
	local scale = gap == 0 and 1 or (gap > 0 and POW10_POS[gap] or POW10_NEG[-gap])
	local scaled = am * scale
	local q = floor(scaled / bm)
	local m, e = normalizeRaw(scaled - q * bm, be)
	return {m, e}
end

-- Combinatorics / special functions
local LOG10_FACTORIAL_CACHE = {0}
for i = 1, 256 do LOG10_FACTORIAL_CACHE[i + 1] = LOG10_FACTORIAL_CACHE[i] + log10(i) end
local FACT_M = {1}
local FACT_E = {0}
do
	local rm, re = 1, 0
	for i = 1, 256 do
		if i > 1 then
			local im, ie = positiveIntegerRaw(i)
			rm, re = mulRaw(rm, re, im, ie)
		end
		FACT_M[i + 1], FACT_E[i + 1] = rm, re
	end
end
local function log10FactorialNumber(n: number): number
	if n <= 1 then return 0 end
	if n <= 256 then return LOG10_FACTORIAL_CACHE[n + 1] end
	local inv = 1 / n
	local inv3 = inv * inv * inv
	return (n + 0.5) * log10(n) - n * LOG10_E + HALF_LOG_TWO_PI * LOG10_E + (inv / 12 - inv3 / 360) * LOG10_E
end
function FastME.log10Factorial(n: number): number
	if n ~= n or n < 0 or n % 1 ~= 0 then return NAN end
	return log10FactorialNumber(n)
end
function FastME.factorial(n: number): Value
	if n ~= n or n < 0 or n % 1 ~= 0 then return {NAN, 0} end
	if n <= 256 then return {FACT_M[n + 1], FACT_E[n + 1]} end
	local m, e = fromLog10Raw(log10FactorialNumber(n)); return {m, e}
end
function FastME.permutation(n: number, k: number): Value
	if n < 0 or k < 0 or k > n or n % 1 ~= 0 or k % 1 ~= 0 then return {NAN, 0} end
	if k == 0 then return {1, 0} end
	if n <= 256 then
		local m, e = divRaw(FACT_M[n + 1], FACT_E[n + 1], FACT_M[n - k + 1], FACT_E[n - k + 1])
		return {m, e}
	end
	if k <= 24 then
		local rm, re = 1, 0
		for i = 0, k - 1 do local im, ie = positiveIntegerRaw(n - i); rm, re = mulRaw(rm, re, im, ie) end
		return {rm, re}
	end
	local m, e = fromLog10Raw(log10FactorialNumber(n) - log10FactorialNumber(n - k)); return {m, e}
end
FastME.nPr = FastME.permutation
function FastME.combination(n: number, k: number): Value
	if n < 0 or k < 0 or k > n or n % 1 ~= 0 or k % 1 ~= 0 then return {NAN, 0} end
	if k == 0 or k == n then return {1, 0} end
	k = min(k, n - k)
	if n <= 256 then
		local dm, de = mulRaw(FACT_M[k + 1], FACT_E[k + 1], FACT_M[n - k + 1], FACT_E[n - k + 1])
		local m, e = divRaw(FACT_M[n + 1], FACT_E[n + 1], dm, de)
		return {m, e}
	end
	if k <= 16 then
		local rm, re = 1, 0
		for i = 1, k do
			local nm, ne = positiveIntegerRaw(n - k + i)
			rm, re = mulRaw(rm, re, nm, ne)
			local dm, de = positiveIntegerRaw(i)
			rm, re = divRaw(rm, re, dm, de)
		end
		return {rm, re}
	end
	local m, e = fromLog10Raw(log10FactorialNumber(n) - log10FactorialNumber(k) - log10FactorialNumber(n - k)); return {m, e}
end
FastME.nCr = FastME.combination

local function logGammaNumber(z: number): number
	if z <= 0 then return NAN end
	if z < 0.5 then return log(PI) - log(sin(PI * z)) - logGammaNumber(1 - z) end
	z = z - 1
	local x = 0.99999999999980993
	x = x + 676.5203681218851 / (z + 1)
	x = x - 1259.1392167224028 / (z + 2)
	x = x + 771.32342877765313 / (z + 3)
	x = x - 176.61502916214059 / (z + 4)
	x = x + 12.507343278686905 / (z + 5)
	x = x - 0.13857109526572012 / (z + 6)
	x = x + 9.9843695780195716e-6 / (z + 7)
	x = x + 1.5056327351493116e-7 / (z + 8)
	local t = z + 7.5
	return HALF_LOG_TWO_PI + (z + 0.5) * log(t) - t + log(x)
end
function FastME.logGamma(x: number): number return logGammaNumber(x) end
function FastME.gamma(x: number): Value
	local lg = logGammaNumber(x)
	if lg ~= lg then return {NAN, 0} end
	local m, e = fromLog10Raw(lg / LN10); return {m, e}
end
function FastME.beta(x: number, y: number): Value
	if x <= 0 or y <= 0 then return {NAN, 0} end
	local sum = x + y
	local lgSum
	if sum % 1 == 0 and sum <= 257 then lgSum = LOG10_FACTORIAL_CACHE[sum] * LN10 else lgSum = logGammaNumber(sum) end
	local m, e = fromLog10Raw((logGammaNumber(x) + logGammaNumber(y) - lgSum) / LN10); return {m, e}
end

-- Trigonometry. Large FastME values cannot retain meaningful angle-reduction precision.
local function trigInput(a: Value): number?
	local x = toNumberRaw(a[1], a[2])
	if x ~= x or x == POS_INF or x == NEG_INF then return nil end
	return x
end
function FastME.sin(a: Value): Value local x = trigInput(a); if not x then return {NAN, 0} end; local m, e = boundedNumberRaw(sin(x)); return {m, e} end
function FastME.cos(a: Value): Value local x = trigInput(a); if not x then return {NAN, 0} end; local m, e = boundedNumberRaw(cos(x)); return {m, e} end
function FastME.tan(a: Value): Value local x = trigInput(a); if not x then return {NAN, 0} end; local m, e = fromNumberRaw(tan(x)); return {m, e} end
function FastME.asin(a: Value): Value local x = trigInput(a); if not x or x < -1 or x > 1 then return {NAN, 0} end; local m, e = boundedNumberRaw(asin(x)); return {m, e} end
function FastME.acos(a: Value): Value local x = trigInput(a); if not x or x < -1 or x > 1 then return {NAN, 0} end; local m, e = boundedNumberRaw(acos(x)); return {m, e} end
function FastME.atan(a: Value): Value local m, e = fromNumberRaw(atan(toNumberRaw(a[1], a[2]))); return {m, e} end
function FastME.rad(a: Value): Value
	local m, e = mulRaw(a[1], a[2], DEG_TO_RAD_M, DEG_TO_RAD_E)
	return {m, e}
end
function FastME.deg(a: Value): Value
	local m, e = mulRaw(a[1], a[2], RAD_TO_DEG_M, RAD_TO_DEG_E)
	return {m, e}
end

-- Aggregates
function FastME.sum(values: {Value}): Value
	local n = #values
	if n == 0 then return {0, 0} end
	local first = values[1]
	local fe = first[2]
	local sm = first[1]
	local i = 2
	while i <= n do
		local v = values[i]
		if v[2] ~= fe then break end
		sm = sm + v[1]
		i = i + 1
	end
	if i > n then local m,e=normalizeRaw(sm,fe); return {m,e} end
	local rm, re
	if i == 2 then rm, re = sm, fe else rm, re = normalizeRaw(sm, fe) end
	for j = i, n do local v = values[j]; rm, re = addRaw(rm, re, v[1], v[2]) end
	return {rm, re}
end
function FastME.product(values: {Value}): Value
	local n = #values
	if n == 0 then return {1, 0} end
	local first = values[1]
	local rm, re = first[1], first[2]
	for i = 2, n do
		local v = values[i]
		local vm, ve = v[1], v[2]
		if rm == rm and vm == vm and rm ~= POS_INF and rm ~= NEG_INF and vm ~= POS_INF and vm ~= NEG_INF then
			if rm == 0 or vm == 0 then rm, re = 0, 0
			else
				local m = rm * vm
				re = re + ve
				if m >= 10 or m <= -10 then rm, re = m * 0.1, re + 1
				elseif m > -1 and m < 1 then rm, re = m * 10, re - 1
				else rm = m end
			end
		else
			rm, re = mulRaw(rm, re, vm, ve)
		end
	end
	return {rm, re}
end
function FastME.average(values: {Value}): Value
	local n = #values
	if n == 0 then return {NAN, 0} end
	local first = values[1]
	local fe = first[2]
	local sm = first[1]
	local i = 2
	while i <= n do
		local v = values[i]
		if v[2] ~= fe then break end
		sm = sm + v[1]
		i = i + 1
	end
	if i > n then local m,e=normalizeRaw(sm / n,fe); return {m,e} end
	local rm, re
	if i == 2 then rm, re = sm, fe else rm, re = normalizeRaw(sm, fe) end
	for j = i, n do local v = values[j]; rm, re = addRaw(rm, re, v[1], v[2]) end
	local m, e = divScalarRaw(rm, re, n)
	return {m, e}
end
function FastME.minOf(values: {Value}): Value?
	local n = #values
	if n == 0 then return nil end
	local best = values[1]
	local bm, be = best[1], best[2]
	for i = 2, n do
		local v = values[i]
		local vm, ve = v[1], v[2]
		local take
		if vm >= 0 and bm >= 0 and vm == vm and bm == bm and vm ~= POS_INF and bm ~= POS_INF then
			if vm == 0 then take = bm > 0 elseif bm == 0 then take = false elseif ve ~= be then take = ve < be else take = vm < bm end
		else take = compareRaw(vm, ve, bm, be) < 0 end
		if take then best, bm, be = v, vm, ve end
	end
	return {bm, be}
end
function FastME.maxOf(values: {Value}): Value?
	local n = #values
	if n == 0 then return nil end
	local best = values[1]
	local bm, be = best[1], best[2]
	for i = 2, n do
		local v = values[i]
		local vm, ve = v[1], v[2]
		local take
		if vm >= 0 and bm >= 0 and vm == vm and bm == bm and vm ~= POS_INF and bm ~= POS_INF then
			if bm == 0 then take = vm > 0 elseif vm == 0 then take = false elseif ve ~= be then take = ve > be else take = vm > bm end
		else take = compareRaw(vm, ve, bm, be) > 0 end
		if take then best, bm, be = v, vm, ve end
	end
	return {bm, be}
end

-- Zero-allocation output operations
-- Each kernel is evaluated exactly once. Besides being faster, this preserves the
-- intended single-operation semantics for the mutable API.
function FastME.set(out: Value, m: number, e: number): Value out[1], out[2] = m, e; return out end
function FastME.copyInto(out: Value, a: Value): Value out[1], out[2] = a[1], a[2]; return out end
function FastME.addInto(out: Value, a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then out[1], out[2] = NAN, 0; return out end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then out[1], out[2] = NAN, 0; return out end
		out[1], out[2] = am, 0; return out
	end
	if bm == POS_INF or bm == NEG_INF then out[1], out[2] = bm, 0; return out end
	if am == 0 then out[1], out[2] = bm, be; return out end
	if bm == 0 then out[1], out[2] = am, ae; return out end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then out[1], out[2] = am, ae; return out end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then out[1], out[2] = 0, 0; return out end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then out[1], out[2] = m, ae; return out end
	if m >= 10 or m <= -10 then out[1], out[2] = m * 0.1, ae + 1; return out end
	if m >= 0.1 or m <= -0.1 then out[1], out[2] = m * 10, ae - 1; return out end
	local av = abs(m)
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then m = m * POW10_POS[-shift]
	else m = m / POW10_SCALE[shift + 309] end
	ae = ae + shift
	av = abs(m)
	if av >= 10 then out[1], out[2] = m * 0.1, ae + 1; return out end
	if av < 1 then out[1], out[2] = m * 10, ae - 1; return out end
	out[1], out[2] = m, ae; return out
end
function FastME.subInto(out: Value, a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], -b[1], b[2]
	if am ~= am or bm ~= bm then out[1], out[2] = NAN, 0; return out end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then out[1], out[2] = NAN, 0; return out end
		out[1], out[2] = am, 0; return out
	end
	if bm == POS_INF or bm == NEG_INF then out[1], out[2] = bm, 0; return out end
	if am == 0 then out[1], out[2] = bm, be; return out end
	if bm == 0 then out[1], out[2] = am, ae; return out end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then out[1], out[2] = am, ae; return out end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then out[1], out[2] = 0, 0; return out end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then out[1], out[2] = m, ae; return out end
	if m >= 10 or m <= -10 then out[1], out[2] = m * 0.1, ae + 1; return out end
	if m >= 0.1 or m <= -0.1 then out[1], out[2] = m * 10, ae - 1; return out end
	local av = abs(m)
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then m = m * POW10_POS[-shift]
	else m = m / POW10_SCALE[shift + 309] end
	ae = ae + shift
	av = abs(m)
	if av >= 10 then out[1], out[2] = m * 0.1, ae + 1; return out end
	if av < 1 then out[1], out[2] = m * 10, ae - 1; return out end
	out[1], out[2] = m, ae; return out
end
function FastME.mulInto(out: Value, a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	local m = am * bm
	local magnitude = abs(m)
	-- IEEE multiplication resolves NaN, infinity and zero-times-infinity.
	if not (magnitude < POS_INF) then out[1], out[2] = m, 0; return out end
	if m == 0 then out[1], out[2] = 0, 0; return out end
	local e = ae + be
	if magnitude >= 10 then out[1], out[2] = m * 0.1, e + 1; return out end
	if magnitude < 1 then out[1], out[2] = m * 10, e - 1; return out end
	out[1], out[2] = m, e; return out
end
function FastME.divInto(out: Value, a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if bm == 0 then
		if am == 0 or am ~= am then out[1], out[2] = NAN, 0; return out end
		out[1], out[2] = am > 0 and POS_INF or NEG_INF, 0; return out
	end
	local m = am / bm
	local magnitude = abs(m)
	if not (magnitude < POS_INF) then out[1], out[2] = m, 0; return out end
	if m == 0 then out[1], out[2] = 0, 0; return out end
	local e = ae - be
	if magnitude < 1 then out[1], out[2] = m * 10, e - 1; return out end
	if magnitude >= 10 then out[1], out[2] = m * 0.1, e + 1; return out end
	out[1], out[2] = m, e; return out
end
function FastME.powInto(out: Value, a: Value, p: number): Value out[1], out[2] = powRaw(a[1], a[2], p); return out end

-- In-place operations
function FastME.iadd(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if am ~= am or bm ~= bm then a[1], a[2] = NAN, 0; return a end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then a[1], a[2] = NAN, 0; return a end
		a[1], a[2] = am, 0; return a
	end
	if bm == POS_INF or bm == NEG_INF then a[1], a[2] = bm, 0; return a end
	if am == 0 then a[1], a[2] = bm, be; return a end
	if bm == 0 then a[1], a[2] = am, ae; return a end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then a[1], a[2] = am, ae; return a end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then a[1], a[2] = 0, 0; return a end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then a[1], a[2] = m, ae; return a end
	if m >= 10 or m <= -10 then a[1], a[2] = m * 0.1, ae + 1; return a end
	if m >= 0.1 or m <= -0.1 then a[1], a[2] = m * 10, ae - 1; return a end
	local av = abs(m)
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then m = m * POW10_POS[-shift]
	else m = m / POW10_SCALE[shift + 309] end
	ae = ae + shift
	av = abs(m)
	if av >= 10 then a[1], a[2] = m * 0.1, ae + 1; return a end
	if av < 1 then a[1], a[2] = m * 10, ae - 1; return a end
	a[1], a[2] = m, ae; return a
end
function FastME.isub(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], -b[1], b[2]
	if am ~= am or bm ~= bm then a[1], a[2] = NAN, 0; return a end
	if am == POS_INF or am == NEG_INF then
		if bm == -am then a[1], a[2] = NAN, 0; return a end
		a[1], a[2] = am, 0; return a
	end
	if bm == POS_INF or bm == NEG_INF then a[1], a[2] = bm, 0; return a end
	if am == 0 then a[1], a[2] = bm, be; return a end
	if bm == 0 then a[1], a[2] = am, ae; return a end
	if ae < be then am, bm, ae, be = bm, am, be, ae end
	local d = ae - be
	if d > 17 then a[1], a[2] = am, ae; return a end
	local m = d == 0 and (am + bm) or (am + bm * POW10_NEG[d])
	if m == 0 then a[1], a[2] = 0, 0; return a end
	if (m >= 1 and m < 10) or (m <= -1 and m > -10) then a[1], a[2] = m, ae; return a end
	if m >= 10 or m <= -10 then a[1], a[2] = m * 0.1, ae + 1; return a end
	if m >= 0.1 or m <= -0.1 then a[1], a[2] = m * 10, ae - 1; return a end
	local av = abs(m)
	local shift = floor(log10(av))
	if shift > 0 and shift <= 17 then m = m * POW10_NEG[shift]
	elseif shift < 0 and shift >= -17 then m = m * POW10_POS[-shift]
	else m = m / POW10_SCALE[shift + 309] end
	ae = ae + shift
	av = abs(m)
	if av >= 10 then a[1], a[2] = m * 0.1, ae + 1; return a end
	if av < 1 then a[1], a[2] = m * 10, ae - 1; return a end
	a[1], a[2] = m, ae; return a
end
function FastME.imul(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	local m = am * bm
	local magnitude = abs(m)
	-- IEEE multiplication resolves NaN, infinity and zero-times-infinity.
	if not (magnitude < POS_INF) then a[1], a[2] = m, 0; return a end
	if m == 0 then a[1], a[2] = 0, 0; return a end
	local e = ae + be
	if magnitude >= 10 then a[1], a[2] = m * 0.1, e + 1; return a end
	if magnitude < 1 then a[1], a[2] = m * 10, e - 1; return a end
	a[1], a[2] = m, e; return a
end
function FastME.idiv(a: Value, b: Value): Value
	local am, ae, bm, be = a[1], a[2], b[1], b[2]
	if bm == 0 then
		if am == 0 or am ~= am then a[1], a[2] = NAN, 0; return a end
		a[1], a[2] = am > 0 and POS_INF or NEG_INF, 0; return a
	end
	local m = am / bm
	local magnitude = abs(m)
	if not (magnitude < POS_INF) then a[1], a[2] = m, 0; return a end
	if m == 0 then a[1], a[2] = 0, 0; return a end
	local e = ae - be
	if magnitude < 1 then a[1], a[2] = m * 10, e - 1; return a end
	if magnitude >= 10 then a[1], a[2] = m * 0.1, e + 1; return a end
	a[1], a[2] = m, e; return a
end
function FastME.isquare(a: Value): Value
	local m, e = a[1], a[2]
	local r = m * m
	if not (r < POS_INF) then a[1], a[2] = r, 0; return a end
	if r == 0 then a[1], a[2] = 0, 0; return a end
	local re = e + e
	if r >= 10 then a[1], a[2] = r * 0.1, re + 1; return a end
	a[1], a[2] = r, re; return a
end
function FastME.isqrt(a: Value): Value
	local m, e = a[1], a[2]
	if m ~= m or m < 0 then a[1], a[2] = NAN, 0; return a end
	if m == 0 then a[1], a[2] = 0, 0; return a end
	if m == POS_INF then a[1], a[2] = POS_INF, 0; return a end
	if e % 2 ~= 0 then m = m * 10; e = e - 1 end
	a[1], a[2] = sqrt(m), e * 0.5; return a
end
function FastME.ipow(a: Value, p: number): Value a[1], a[2] = powRaw(a[1], a[2], p); return a end
function FastME.ineg(a: Value): Value a[1] = -a[1]; return a end
function FastME.iabs(a: Value): Value a[1] = abs(a[1]); return a end
function FastME.ifma(a, b, c)
	local m, e = mulRaw(a[1], a[2], b[1], b[2])
	a[1], a[2] = addRaw(m, e, c[1], c[2])
	return a
end

-- Formatting
FastME.FormatConfig = {
	Precision = 2,
	MaxPrecision = 8,
	EStart = 3000,
	ScientificStart = -6,
	TrimZeros = false,
}

local FIXED_SUFFIXES = {
	[0] = "", [1] = "K", [2] = "M", [3] = "B", [4] = "T",
	[5] = "Qa", [6] = "Qi", [7] = "Sx", [8] = "Sp", [9] = "Oc", [10] = "No",
	[11] = "Dc", [12] = "Ud", [13] = "Dd", [14] = "Td", [15] = "Qad", [16] = "Qid",
	[17] = "Sxd", [18] = "Spd", [19] = "Ocd", [20] = "Nod", [21] = "Vg",
}
local UNIT_PREFIX = {[0]="",[1]="U",[2]="D",[3]="T",[4]="Qa",[5]="Qi",[6]="Sx",[7]="Sp",[8]="Oc",[9]="No"}
local TENS_SUFFIX = {[0]="",[1]="Dc",[2]="Vg",[3]="Tg",[4]="Qag",[5]="Qig",[6]="Sxg",[7]="Spg",[8]="Og",[9]="Ng"}
local HUNDREDS_SUFFIX = {[0]="",[1]="Ce",[2]="Dce",[3]="Tce",[4]="Qace",[5]="Qice",[6]="Sxce",[7]="Spce",[8]="Oce",[9]="Nce"}
local SUFFIX_CACHE = {}
for k, v in pairs(FIXED_SUFFIXES) do SUFFIX_CACHE[k] = v end

local function appendSuffix(current, part)
	if part == "" then return current end
	if current == "" then return part end
	return current .. strLower(strSub(part, 1, 1)) .. strSub(part, 2)
end
local function generateSuffix(group: number): string?
	local cached = SUFFIX_CACHE[group]
	if cached ~= nil then return cached end
	if group <= 0 then return "" end
	local index = group - 1
	if index > 999 then return nil end
	local units = index % 10
	local tens = floor(index / 10) % 10
	local hundreds = floor(index / 100) % 10
	local r = UNIT_PREFIX[units] .. TENS_SUFFIX[tens] .. HUNDREDS_SUFFIX[hundreds]
	if r == "" then return nil end
	SUFFIX_CACHE[group] = r
	return r
end
FastME.getSuffix = generateSuffix

local EXPONENT_SUFFIXES = {"", "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No"}
local EXPONENT_SCALE = {[1]=1e3,[2]=1e6,[3]=1e9,[4]=1e12,[5]=1e15,[6]=1e18,[7]=1e21,[8]=1e24,[9]=1e27,[10]=1e30}
local ROUND_SCALE = {[0]=1,[1]=10,[2]=100,[3]=1e3,[4]=1e4,[5]=1e5,[6]=1e6,[7]=1e7,[8]=1e8}
local function trimZeros(s: string): string
	local n = #s
	local dot = 0
	for i = 1, n do
		if strByte(s, i) == 46 then dot = i; break end
	end
	if dot == 0 then return s end
	local last = n
	while last > dot and strByte(s, last) == 48 do last = last - 1 end
	if last == dot then last = last - 1 end
	if last == n then return s end
	return strSub(s, 1, last)
end
local FIXED_FORMAT = {}
local GENERAL_FORMAT = {}
local FIXED_EXP_FORMAT = {}
for i = 0, 16 do
	FIXED_FORMAT[i] = "%." .. i .. "f"
	GENERAL_FORMAT[i] = "%." .. i .. "g"
	FIXED_EXP_FORMAT[i] = "%." .. i .. "fe%d"
end
local function fixed(value: number, decimals: number, trim: boolean): string
	local r
	if decimals == 2 then r = strFormat("%.2f", value)
	elseif decimals == 0 then r = strFormat("%.0f", value)
	elseif decimals == 1 then r = strFormat("%.1f", value)
	elseif decimals == 3 then r = strFormat("%.3f", value)
	elseif decimals == 6 then r = strFormat("%.6f", value)
	else
		local fmt = FIXED_FORMAT[decimals]
		r = strFormat(fmt or ("%." .. decimals .. "f"), value)
	end
	return trim and trimZeros(r) or r
end
local function compactScalar(value: number, precision: number): string
	if value == 0 then return "0" end
	local sign = ""
	if value < 0 then sign = "-"; value = -value end
	if value < 1000 then
		if value % 1 == 0 then return sign .. tostring(value) end
		local r = precision == 2 and strFormat("%.2f", value) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), value)
		return sign .. trimZeros(r)
	end
	local group
	if value < 1e6 then group = 1
	elseif value < 1e9 then group = 2
	elseif value < 1e12 then group = 3
	elseif value < 1e15 then group = 4
	elseif value < 1e18 then group = 5
	elseif value < 1e21 then group = 6
	elseif value < 1e24 then group = 7
	elseif value < 1e27 then group = 8
	elseif value < 1e30 then group = 9
	elseif value < 1e33 then group = 10
	else group = floor(log10(value) / 3) end
	if group <= 10 then
		local scaled = value / EXPONENT_SCALE[group]
		local r = precision == 2 and strFormat("%.2f", scaled) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), scaled)
		return sign .. trimZeros(r) .. EXPONENT_SUFFIXES[group + 1]
	end
	return sign .. strFormat("%.3e", value)
end
FastME.formatExponent = compactScalar

function FastME.toScientific(a: Value, precision: number?): string
	precision = floor(precision or 2)
	local m, e = a[1], a[2]
	if m ~= m then return "NaN" end
	if m == POS_INF then return "Infinity" end
	if m == NEG_INF then return "-Infinity" end
	if m == 0 then return "0" end
	local trim = FastME.FormatConfig.TrimZeros
	if not trim and e % 1 == 0 and e >= -2147483648 and e <= 2147483647 then
		return strFormat(FIXED_EXP_FORMAT[precision] or ("%." .. precision .. "fe%d"), m, e)
	end
	local r
	if precision == 2 then r = strFormat("%.2f", m)
	else r = strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), m) end
	if trim then r = trimZeros(r) end
	return r .. "e" .. tostring(e)
end
function FastME.toEngineering(a: Value, precision: number?): string
	precision = floor(precision or 2)
	local m, e = a[1], a[2]
	if m ~= m then return "NaN" end
	if m == POS_INF then return "Infinity" end
	if m == NEG_INF then return "-Infinity" end
	if m == 0 then return "0" end
	local ee = floor(e / 3) * 3
	local shift = e - ee
	if shift == 1 then m = m * 10 elseif shift == 2 then m = m * 100 end
	local trim = FastME.FormatConfig.TrimZeros
	if not trim and ee >= -2147483648 and ee <= 2147483647 then
		return strFormat(FIXED_EXP_FORMAT[precision] or ("%." .. precision .. "fe%d"), m, ee)
	end
	local r
	if precision == 2 then r = strFormat("%.2f", m)
	else r = strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), m) end
	if trim then r = trimZeros(r) end
	return r .. "e" .. tostring(ee)
end
function FastME.toSuffix(a: Value, precision: number?): string
	precision = floor(precision or FastME.FormatConfig.Precision)
	if precision < 0 then precision = 0 elseif precision > FastME.FormatConfig.MaxPrecision then precision = FastME.FormatConfig.MaxPrecision end
	local trim = FastME.FormatConfig.TrimZeros
	local m, e = a[1], a[2]
	if m ~= m then return "NaN" end
	if m == POS_INF then return "Infinity" end
	if m == NEG_INF then return "-Infinity" end
	if m == 0 then return "0" end
	if e < FastME.FormatConfig.ScientificStart then
		if not trim and e % 1 == 0 and e >= -2147483648 and e <= 2147483647 then
			return strFormat(FIXED_EXP_FORMAT[precision] or ("%." .. precision .. "fe%d"), m, e)
		end
		local r = precision == 2 and strFormat("%.2f", m) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), m)
		if trim then r = trimZeros(r) end
		return r .. "e" .. tostring(e)
	end
	if e < 3 then
		local value = toNumberRaw(m, e)
		local r = precision == 2 and strFormat("%.2f", value) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), value)
		return trim and trimZeros(r) or r
	end
	if e >= FastME.FormatConfig.EStart then
		local ex = compactScalar(e, precision)
		if m == 1 then return "E" .. ex end
		if m == -1 then return "-E" .. ex end
		local r = precision == 2 and strFormat("%.2f", m) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), m)
		if trim then r = trimZeros(r) end
		return r .. "E" .. ex
	end
	local group = floor(e / 3)
	local shift = e - group * 3
	local value = m
	if shift == 1 then value = value * 10 elseif shift == 2 then value = value * 100 end
	local p = ROUND_SCALE[precision] or (10 ^ precision)
	if floor(abs(value) * p + 0.5) / p >= 1000 then value = value * 0.001; group = group + 1 end
	local suffix = FIXED_SUFFIXES[group]
	if suffix == nil then suffix = generateSuffix(group) end
	if suffix == nil then
		if not trim and e % 1 == 0 and e >= -2147483648 and e <= 2147483647 then
			return strFormat(FIXED_EXP_FORMAT[precision] or ("%." .. precision .. "fe%d"), m, e)
		end
		local r = precision == 2 and strFormat("%.2f", m) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), m)
		if trim then r = trimZeros(r) end
		return r .. "e" .. tostring(e)
	end
	local r = precision == 2 and strFormat("%.2f", value) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), value)
	if trim then r = trimZeros(r) end
	return r .. suffix
end
FastME.format = FastME.toSuffix
function FastME.toString(a: Value, precision: number?): string
	precision = floor(precision or 6)
	local m,e=a[1],a[2]
	if m ~= m then return "NaN" end
	if m == POS_INF then return "Infinity" end
	if m == NEG_INF then return "-Infinity" end
	if m == 0 then return "0" end
	if e >= -4 and e <= 15 then
		local value
		if e == 0 then value = m
		elseif e > 0 then value = m * POW10_POS[e]
		else value = m * POW10_NEG[-e] end
		if precision == 6 then return strFormat("%.6g", value) end
		return strFormat(GENERAL_FORMAT[precision] or ("%." .. precision .. "g"), value)
	end
	local trim = FastME.FormatConfig.TrimZeros
	if not trim and e % 1 == 0 and e >= -2147483648 and e <= 2147483647 then
		return strFormat(FIXED_EXP_FORMAT[precision] or ("%." .. precision .. "fe%d"), m, e)
	end
	local r = precision == 6 and strFormat("%.6f", m) or strFormat(FIXED_FORMAT[precision] or ("%." .. precision .. "f"), m)
	if trim then r = trimZeros(r) end
	return r .. "e" .. tostring(e)
end

local PARSE_SUFFIX = {
	K=3,k=3,M=6,m=6,B=9,b=9,T=12,t=12,
	QA=15,Qa=15,qa=15,QI=18,Qi=18,qi=18,SX=21,Sx=21,sx=21,SP=24,Sp=24,sp=24,
	OC=27,Oc=27,oc=27,NO=30,No=30,no=30,DC=33,Dc=33,dc=33,UD=36,Ud=36,ud=36,
	DD=39,Dd=39,dd=39,TD=42,Td=42,td=42,QAD=45,Qad=45,qad=45,QID=48,Qid=48,qid=48,
	SXD=51,Sxd=51,sxd=51,SPD=54,Spd=54,spd=54,OCD=57,Ocd=57,ocd=57,NOD=60,Nod=60,nod=60,
	VG=63,Vg=63,vg=63,
}
function FastME.fromFormattedString(s: string): Value
	local n = #s
	if n == 0 then return {NAN, 0} end
	local split = n
	while split > 0 do
		local c = strByte(s, split)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) then split = split - 1 else break end
	end
	if split == n then
		local m, e = fromStringRaw(s)
		return {m, e}
	end
	if split == 0 then return {NAN, 0} end
	local suffix = strSub(s, split + 1)
	local exponent = PARSE_SUFFIX[suffix]
	if exponent == nil then exponent = PARSE_SUFFIX[strUpper(suffix)] end
	if exponent == nil then return {NAN, 0} end
	local bm, be = fromStringRaw(strSub(s, 1, split))
	if bm ~= bm then return {bm, be} end
	if bm == 0 then return {0, 0} end
	return {bm, be + exponent}
end

function FastME.serialize(a: Value): string
	local m = a[1]
	if m ~= m then return "nan@0" end
	if m == POS_INF then return "inf@0" end
	if m == NEG_INF then return "-inf@0" end
	local e = a[2]
	if e % 1 == 0 and e >= -2147483648 and e <= 2147483647 then
		return strFormat("%.17g@%d", a[1], e)
	end
	return strFormat("%.17g@%.17g", a[1], e)
end

function FastME.deserialize(s: string): Value
	local n = #s
	if n < 3 then return {NAN, 0} end

	-- Serialized values place @ immediately before the exponent. Scanning from
	-- the end normally touches only the exponent bytes instead of the mantissa.
	local p = n - 1
	while p > 1 and strByte(s, p) ~= 64 do p = p - 1 end
	if p <= 1 then return {NAN, 0} end

	local mText = strLower(strSub(s, 1, p - 1))
	local exponentText = strSub(s, p + 1)
	local e = tonumber(exponentText)
	if e == nil or e ~= e or e == POS_INF or e == NEG_INF or e % 1 ~= 0 then return {NAN, 0} end
	local m
	if mText == "nan" or mText == "-nan" then return {NAN, 0} end
	if mText == "inf" or mText == "+inf" or mText == "infinity" then m = POS_INF
	elseif mText == "-inf" or mText == "-infinity" then m = NEG_INF
	else m = tonumber(mText) end
	if m == nil then return {NAN, 0} end
	local rm, re = normalizeRaw(m, e)
	return {rm, re}
end

function FastME.squareInto(out: Value, a: Value): Value
	local m, e = a[1], a[2]
	local r = m * m
	if not (r < POS_INF) then out[1], out[2] = r, 0; return out end
	if r == 0 then out[1], out[2] = 0, 0; return out end
	local re = e + e
	if r >= 10 then out[1], out[2] = r * 0.1, re + 1; return out end
	out[1], out[2] = r, re; return out
end

function FastME.sqrtInto(out: Value, a: Value): Value
	local m, e = a[1], a[2]
	if m ~= m or m < 0 then out[1], out[2] = NAN, 0; return out end
	if m == 0 then out[1], out[2] = 0, 0; return out end
	if m == POS_INF then out[1], out[2] = POS_INF, 0; return out end
	if e % 2 ~= 0 then m = m * 10; e = e - 1 end
	out[1], out[2] = sqrt(m), e * 0.5; return out
end

-- Pair API: normalized mantissa/exponent arguments; no result tables allocated.
FastME.normalizeRaw = normalizeRaw
FastME.fromNumberRaw = fromNumberRaw
FastME.fromStringRaw = fromStringRaw
FastME.toNumberRaw = toNumberRaw
FastME.addRaw = addRaw
FastME.subRaw = subRaw
FastME.mulRaw = mulRaw
FastME.divRaw = divRaw
FastME.scaleRaw = scaleRaw
FastME.divScalarRaw = divScalarRaw
FastME.recipRaw = recipRaw
FastME.squareRaw = squareRaw
FastME.sqrtRaw = sqrtRaw
FastME.fromLog10Raw = fromLog10Raw
FastME.powIntRaw = powIntRaw
FastME.powRaw = powRaw
FastME.compareRaw = compareRaw

return FastME