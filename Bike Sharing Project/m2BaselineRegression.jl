### A Pluto.jl notebook ###
# v1.0.4

#> [frontmatter]
#> title = "M2 · Baseline Linear Regression — Bike Sharing"
#> description = "Midterm project milestone 2: baseline multiple linear regression of daily Capital Bikeshare rentals with diagnostics and partial-effect plots."

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ c44336d3-0c16-5409-98fb-d90af0d9fdb8
begin
	using CSV, DataFrames, Dates, Downloads, Printf, ZipFile
	using GLM, StatsModels, StatsBase, Distributions, HypothesisTests
	using LinearAlgebra, Random, Statistics
	using Loess, PlotlyKaleido, PlutoPlotly, PlutoUI
end

# ╔═╡ ebffea60-3284-50a6-a187-2530b8a0d84a
md"""
# Midterm Project · M2 — Baseline Linear Regression
### Daily Capital Bikeshare rentals, Washington, D.C. (2011–2012)

This notebook completes **Milestone 2 (Baseline Linear Regression)** of the midterm project for the *bike sharing* dataset:

* fit a multiple linear model for a continuous outcome, the total number of bike rentals per day (`cnt`);
* check the assumptions: linearity, constant variance, normality of the residuals, and leverage/influence (plus independence, because the observations are consecutive days);
* interpret the key coefficients with partial-effect plots.

The analysis follows the template of the **Exam 1 review**: state the model and the distribution of the errors, build confidence intervals and hypothesis tests step by step, compare nested models with an ``F``-test, diagnose multicollinearity from the summary block and the VIFs, select terms with backward AIC/BIC, and read the residual plots. Each section names the review problem it mirrors.

**Project question** (answered fully in M3): *after adjusting for weather, is the holiday effect meaningful, and does it depend on temperature?* The model built here is the baseline that the M3 ANCOVA will extend.
"""

# ╔═╡ a63d3d12-1165-5a5a-a889-4c1bc9d4a6ab
TableOfContents(title = "M2 · Bike sharing", depth = 3)

# ╔═╡ efccf287-e8e7-549a-bba7-38b0b6fe6726
md"""
## 1 · Data

The data are the daily file (`day.csv`) of the UCI *Bike Sharing* dataset (Fanaee-T & Gama, 2013): 731 days of Capital Bikeshare rentals in Washington, D.C., from 1 January 2011 to 31 December 2012, joined with weather and calendar information. A copy is stored in `data/day.csv` next to this notebook; if it is missing, the notebook downloads the archive from the UCI repository.
"""

# ╔═╡ 562689cd-12a1-5c6b-b8ac-b25f7b688993
data_path = joinpath(@__DIR__, "data", "day.csv")

# ╔═╡ 0305acd4-985a-55d8-957a-03d0921fb789
"""
    load_bike_data(path)

Read the daily UCI *Bike Sharing* file. When `path` does not exist, download the
archive from the UCI Machine Learning Repository and extract `day.csv` to `path`.
"""
function load_bike_data(path)
	if !isfile(path)
		mkpath(dirname(path))
		archive = Downloads.download("https://archive.ics.uci.edu/static/public/275/bike+sharing+dataset.zip")
		reader = ZipFile.Reader(archive)
		try
			entry = only(filter(f -> basename(f.name) == "day.csv", reader.files))
			write(path, read(entry))
		finally
			close(reader)
		end
	end
	CSV.read(path, DataFrame)
end

# ╔═╡ b6912c79-71ea-51c4-9bd6-5ba928ec51a0
bike_raw = load_bike_data(data_path)

# ╔═╡ ad3a6f5f-cd8e-5870-8e82-dc780c1c1a27
md"""
### 1.1 Recoding to interpretable units

The weather variables are stored rescaled to ``[0, 1]``. We convert them back to physical units so that the coefficients read as "rentals per degree", "per percentage point", and so on.

| Variable | Stored as | Converted to |
|:--|:--|:--|
| `temp` | ``(t + 8)/47`` | temperature ``t`` in °C |
| `atemp` | ``(t + 16)/66`` | "feels-like" temperature ``t`` in °C |
| `hum` | ``h/100`` | relative humidity ``h`` in % |
| `windspeed` | ``w/67`` | wind speed ``w`` in km/h |

Two documentation problems are resolved from the data themselves:

* **Temperature scale.** The UCI web page gives the min–max scaling above (``t_{\min} = -8``, ``t_{\max} = 39`` °C); the `Readme.txt` inside the archive says "divided by 41". The min–max version is the physically plausible one: it puts the coldest day (22 Jan 2011) at −5.2 °C rather than +2.4 °C. The choice only rescales the temperature coefficients; fitted values and all tests are identical.
* **Season codes.** `Readme.txt` lists code 1 as spring, but code 1 runs from 1 January to about 20 March (table below), so the codes are 1 = winter, 2 = spring, 3 = summer, 4 = fall.

The flags `holiday`, `workingday` and `weekday` overlap (a working day is a weekday that is not a holiday, and every holiday in the data falls on a weekday), so they are combined into one **day type** factor with levels *working day*, *weekend* and *holiday*. Day type is also the "treatment" for the M3 ANCOVA.
"""

# ╔═╡ feffbc4d-54a4-5d16-86ff-811d2b2d81d6
bike = let d = bike_raw
	DataFrame(
		date       = d.dteday,
		weekday    = Dates.dayabbr.(d.dteday),
		year       = ifelse.(d.yr .== 1, "2012", "2011"),
		month      = Dates.monthabbr.(d.mnth),
		season     = getindex.(Ref(["Winter", "Spring", "Summer", "Fall"]), d.season),
		daytype    = [h == 1 ? "Holiday" : w == 1 ? "Working day" : "Weekend"
		              for (h, w) in zip(d.holiday, d.workingday)],
		weather    = getindex.(Ref(["Clear", "Mist/cloudy", "Light rain/snow", "Heavy rain/snow"]), d.weathersit),
		temp_c     = -8 .+ 47 .* d.temp,
		atemp_c    = -16 .+ 66 .* d.atemp,
		hum_pct    = 100 .* d.hum,
		wind_kmh   = 67 .* d.windspeed,
		casual     = d.casual,
		registered = d.registered,
		cnt        = d.cnt,
	)
end

# ╔═╡ 171d4851-26cc-5768-8d37-956cd08e51b2
missing_values = sum(col -> count(ismissing, col), eachcol(bike_raw))

# ╔═╡ 1bba47d4-70c3-582a-8f77-5aac8e7f06c4
filter(r -> r.hum_pct == 0, bike)

# ╔═╡ bb3b1f2e-1b5d-521f-a296-1192e6170367
dm = let d = filter(r -> r.hum_pct > 0, bike)
	d.tc = d.temp_c .- 20    # temperature centered at 20 °C, used for the polynomial terms
	d.label = [string(Dates.format(r.date, "e d u yyyy"), " · ", r.daytype, " · ", r.weather) for r in eachrow(d)]
	d
end;

# ╔═╡ 9bce7da4-2b09-59b6-8715-b5b4d4166a25
Markdown.parse("""
### 1.2 Data-quality check

The raw file has $(missing_values) missing values. One record is impossible, though: **10 March 2011** is coded as a day of light rain with **0 % relative humidity**. We treat that humidity as a recording error and drop the day, leaving ``n = `` $(nrow(dm)) days for modeling.
""")

# ╔═╡ d7564924-ebaf-558e-b13f-6aeb6e2aeade
Markdown.parse("""
### 1.3 Variables used in M2

Continuous variables (``n = `` $(nrow(dm)) days):
""")

# ╔═╡ bdb16eac-75e6-5fa0-bc10-0b6b3d44b018
md"""
Factors (the first level listed is the reference category in every model):
"""

# ╔═╡ 63e76eb2-021a-53a7-a3c7-ee30469b45d6
md"""
## 2 · First pass: simple linear regression *(Exam 1 review, Problem 1)*

Temperature is the strongest single predictor of daily rentals, so we start with

```math
Y_i = \beta_0 + \beta_1 T_i + \varepsilon_i, \qquad \varepsilon_i \overset{\text{iid}}{\sim} N(0, \sigma^2), \qquad i = 1, \dots, n,
```

where ``Y_i`` is the number of rentals on day ``i`` and ``T_i`` is that day's mean temperature in °C.
"""

# ╔═╡ 6f24e747-2626-5575-bc0b-43c7ce63963e
m_slr = lm(@formula(cnt ~ temp_c), dm);

# ╔═╡ 53dff4ce-a835-50ee-aa1c-123ed4fa6bb5
slr = let m = m_slr
	df = Int(dof_residual(m))
	tcrit = quantile(TDist(df), 0.995)
	b, se = coef(m)[2], stderror(m)[2]
	(b0 = coef(m)[1], b1 = b, se = se, df = df, tcrit = tcrit, lo = b - tcrit * se, hi = b + tcrit * se,
	 σ = sqrt(deviance(m) / df), r2 = r2(m))
end

# ╔═╡ 4d31ac5f-87e4-5533-93e2-a0aa0d1f9979
md"""
## 3 · Baseline multiple regression *(Problem 2)*

Next we add the other weather variables and the calendar factors. With dummy (treatment) coding, each factor is compared with its reference level: 2011, winter, working day and clear weather. Writing ``H`` for humidity (%) and ``W`` for wind speed (km/h):

```math
\begin{aligned}
Y_i = {} & \beta_0 + \beta_1\,\text{Yr2012}_i + \beta_2\,\text{Spring}_i + \beta_3\,\text{Summer}_i + \beta_4\,\text{Fall}_i + \beta_5\,\text{Weekend}_i + \beta_6\,\text{Holiday}_i \\
& + \beta_7\,\text{Mist}_i + \beta_8\,\text{RainSnow}_i + \beta_9\,T_i + \beta_{10}\,H_i + \beta_{11}\,W_i + \varepsilon_i,
\qquad \varepsilon_i \overset{\text{iid}}{\sim} N(0, \sigma^2).
\end{aligned}
```
"""

# ╔═╡ cc226063-d7c0-5f44-a4f9-77909ffad1a4
coding = Dict(
	:year    => DummyCoding(base = "2011", levels = ["2011", "2012"]),
	:season  => DummyCoding(base = "Winter", levels = ["Winter", "Spring", "Summer", "Fall"]),
	:month   => DummyCoding(base = "Jan", levels = Dates.monthabbr.(1:12)),
	:daytype => DummyCoding(base = "Working day", levels = ["Working day", "Weekend", "Holiday"]),
	:weather => DummyCoding(base = "Clear", levels = ["Clear", "Mist/cloudy", "Light rain/snow"]),
)

# ╔═╡ 9449bbe3-afb1-5fc0-980c-bcfc598c158b
f_base = @formula(cnt ~ year + season + daytype + weather + temp_c + hum_pct + wind_kmh)

# ╔═╡ 6d9d63da-cd2a-5310-9c77-ea632bb44839
m_base = lm(f_base, dm; contrasts = coding);

# ╔═╡ 4705ac92-e1b9-521c-9ed9-6a53395c62f1
md"""
## 4 · Is temperature linear? C+R plots and a nested ``F``-test *(Problem 3)*

A **component-plus-residual (partial-residual) plot** shows, for one predictor ``x_j``, the residuals plus the fitted contribution of ``x_j``, that is ``e_i + \hat\beta_j (x_{ij} - \bar x_j)``, against ``x_j``. If the relationship is linear, the LOESS smoother (orange) follows the dashed straight line.
"""

# ╔═╡ ca6eba9e-a96e-5c2e-a738-122b427347a9
md"""
The temperature panel is clearly curved: rentals climb steeply between about 5 °C and 20 °C, level off in the mid-20s and fall on the hottest days, so a straight line under-predicts mild days and over-predicts cold and hot ones. Humidity and wind look roughly linear (Section 8.1 revisits them). We therefore add polynomial terms in the centered temperature ``T = `` temperature − 20 °C (centering reduces the correlation between ``T``, ``T^2`` and ``T^3``) and compare the nested models with ``F``-tests, as R's `anova()` does:
"""

# ╔═╡ e86a54ec-d2ce-5e2d-ae80-1d7274097986
temp_formulas = [
	"Linear"    => f_base,
	"Quadratic" => @formula(cnt ~ year + season + daytype + weather + tc + tc^2 + hum_pct + wind_kmh),
	"Cubic"     => @formula(cnt ~ year + season + daytype + weather + tc + tc^2 + tc^3 + hum_pct + wind_kmh),
	"Quartic"   => @formula(cnt ~ year + season + daytype + weather + tc + tc^2 + tc^3 + tc^4 + hum_pct + wind_kmh),
]

# ╔═╡ d4f3404d-71eb-5e62-89f7-ad1b8ebb6919
m_quad, m_cubic, m_quart = (lm(f, dm; contrasts = coding) for (_, f) in temp_formulas[2:4]);

# ╔═╡ fb2f234a-b2d3-551c-a97a-d3dea1f6d41e
md"""
## 5 · Multicollinearity in a "kitchen-sink" model *(Problem 4)*

Suppose we also add the **feels-like temperature** (`atemp_c`) and **month** (11 dummies) to the cubic model, since both plausibly affect riding. The summary block shows the warning signs of multicollinearity:
"""

# ╔═╡ 6d1f6071-f74b-5c53-afcb-6c0960eb6e01
f_full = @formula(cnt ~ year + season + month + daytype + weather + tc + tc^2 + tc^3 + atemp_c + hum_pct + wind_kmh)

# ╔═╡ b911e4d1-7739-5541-94b8-9c301df5ff5a
m_full = lm(f_full, dm; contrasts = coding);

# ╔═╡ 32bbc87c-3e7c-568c-acd9-e33258492725
md"""
## 6 · Backward selection by AIC and BIC *(Problem 5)*

Starting from the full model, backward elimination drops, one at a time, the term whose removal lowers the criterion the most, and stops when no removal helps. As in R's `step()`, the criterion is ``n \log(\text{RSS}/n) + k\,p`` with ``k = 2`` for AIC and ``k = \log n`` for BIC (this differs from the log-likelihood AIC by a constant). Each factor and the temperature polynomial are treated as one term.
"""

# ╔═╡ 17805076-f655-54ad-8acb-b4a2c2434eb6
selection_terms = [
	"year"        => term(:year),
	"season"      => term(:season),
	"month"       => term(:month),
	"daytype"     => term(:daytype),
	"weather"     => term(:weather),
	"poly(tc, 3)" => @formula(cnt ~ tc + tc^2 + tc^3).rhs,
	"atemp_c"     => term(:atemp_c),
	"hum_pct"     => term(:hum_pct),
	"wind_kmh"    => term(:wind_kmh),
]

# ╔═╡ da508975-08d0-55ac-90aa-81f99ef07e99
md"""
### 6.2 Least squares by hand *(Problem 7)*

The OLS estimator solves the normal equations, ``\hat\beta = (X^\top X)^{-1} X^\top y``. It is unbiased whenever ``E[\varepsilon \mid X] = 0``:

```math
E[\hat\beta] = (X^\top X)^{-1} X^\top E[y] = (X^\top X)^{-1} X^\top X \beta = \beta .
```

Computing ``\hat\beta`` directly from the model matrix reproduces GLM.jl's estimates, and ``\hat\sigma^2 = \text{RSS}/(n - p)``:
"""

# ╔═╡ 65c7c8d7-69a7-50c8-a326-6bfe14aea87e
md"""
### 7.2 Does day type matter? Two ``t``-tests at ``\alpha = 0.05`` *(Problem 2a)*
"""

# ╔═╡ cc46ea37-fa1a-5f23-ae18-eae34ae3faf0
md"""
## 8 · Checking the assumptions *(Problem 6 and M2)*

The inference above assumes (1) a linear mean function, (2) constant error variance, (3) normally distributed errors and (4) independent errors, and it can be distorted by (5) high-leverage or influential days. Each is checked below with plots and a formal test. Hover over any point to see its date.
"""

# ╔═╡ 53d425c4-ec93-5190-9cdf-0a6d3b649bba
md"""
### 8.1 Linearity

With the cubic term, the LOESS curve in the temperature C+R plot follows the fitted component closely. Humidity and wind are close to linear over most of their range, with some extra curvature at the extremes: humidity matters little below about 50 %, and wind matters more above about 20 km/h.
"""

# ╔═╡ 96ed9737-95b4-5f80-8f24-7ca235f6338f
nw_lags = floor(Int, 4 * (nrow(dm) / 100)^(2 / 9))

# ╔═╡ d8ff42f8-1f3e-5c15-85f4-0b5f735b6d3c
Markdown.parse("""
### 8.7 Sensitivity checks

**Robust standard errors.** HC3 standard errors allow the variance to differ from day to day, and Newey–West (HAC) standard errors also allow autocorrelation (Bartlett kernel, $(nw_lags) lags, ``\\lfloor 4 (n/100)^{2/9} \\rfloor``). The ``p``-values below use the Newey–West standard errors:
""")

# ╔═╡ e1171cbd-b81e-5422-aabf-c15c41a9c285
md"""
## 9 · Interpreting the key coefficients *(M2)*

A **partial-effect plot** shows how the predicted number of rentals changes with one predictor while all the other predictors are held fixed. Following the "effect display" convention (Fox & Weisberg), the other predictors are held at their sample averages, with each factor at its observed mix of levels, so the height of each curve corresponds to an average day of the two years. Bands and bars are 95 % confidence intervals for the mean response. Curves span the central 98 % of the observed values; tick marks along the bottom show the observed days. All panels share one vertical scale, so effect sizes can be compared directly.
"""

# ╔═╡ 9cf637e5-ca1b-57f7-b78c-b581b4aeaf86
md"""
## Appendix A · Figures for the M2 paper

The figures in the M2 paper are generated here. Tick the box to write them as PNG files into `figures/` next to this notebook (PlotlyKaleido renders the Plotly figures).
"""

# ╔═╡ 22aefb06-4242-5a19-ae35-144580fe963c
@bind export_figures CheckBox(default = false)

# ╔═╡ 15abc70e-9d9b-5acf-b8f7-f19fbfbb309e
md"""
## Appendix B · Statistical helper functions
"""

# ╔═╡ 858996ad-09da-542f-9e41-d0a85dbf141b
"""
    fmt(x, d = 0)

Format a number with `d` decimals, thousands separators and a true minus sign.
"""
function fmt(x::Real, d::Integer = 0)
	s = Printf.format(Printf.Format("%.$(d)f"), abs(x))
	parts = split(s, '.')
	int = replace(parts[1], r"(?<=\d)(?=(\d{3})+$)" => ",")
	out = length(parts) == 2 ? string(int, ".", parts[2]) : int
	(x < 0 && any(c -> c in '1':'9', s)) ? "−" * out : out
end

# ╔═╡ 5163a58d-1f1d-5f85-9c64-91439be24927
Markdown.parse("""
**(a) The fitted model.** ``\\hat Y`` = $(fmt(slr.b0, 1)) + $(fmt(slr.b1, 2)) ``T``. The errors ``\\varepsilon_i`` are assumed to be an iid sample from a normal distribution with mean 0 and constant variance ``\\sigma^2``; the estimate is ``\\hat\\sigma`` = $(fmt(slr.σ, 1)) rentals/day on $(slr.df) degrees of freedom.

**(b) A 99 % confidence interval for ``\\beta_{\\text{temp}}``.** With ``n - 2`` = $(slr.df) degrees of freedom, the critical value is ``t_{0.995}`` = $(fmt(slr.tcrit, 4)) (`quantile(TDist($(slr.df)), 0.995)`, the Julia version of R's `qt(0.995, $(slr.df))`). The point estimate is $(fmt(slr.b1, 3)) with standard error $(fmt(slr.se, 3)), so the interval is

$(fmt(slr.b1, 3)) ± $(fmt(slr.tcrit, 4)) × $(fmt(slr.se, 3)) = ($(fmt(slr.lo, 1)), $(fmt(slr.hi, 1))).

We are 99 % confident that this interval captures the true temperature slope.

**(c) Interpretation.** For every 1 °C increase in a day's mean temperature, the predicted average number of rentals rises by about $(fmt(slr.b1, 0)) bikes per day. Temperature alone explains ``R^2`` = $(fmt(slr.r2, 3)) of the day-to-day variation, so other predictors are needed.
""")

# ╔═╡ 1c230219-435f-5ee3-a2af-4f3f592da8d6
Markdown.parse("""
Every weather and calendar term except *weekend* is significant at the 5 % level, and ``R^2`` rises from $(fmt(r2(m_slr), 3)) to $(fmt(r2(m_base), 3)). Before interpreting individual coefficients, the next section checks whether a straight line in temperature is adequate.
""")

# ╔═╡ d42ac367-1f08-5df6-9406-45024724852b
"Format a p-value as `< 0.001` or `= 0.123`."
fmt_p(p) = p < 0.001 ? "< 0.001" : "= " * fmt(p, 3)

# ╔═╡ 38160394-806f-5fea-87ce-3ce423b72906
"p-value for a table cell."
pstr(p) = p < 0.001 ? "< 0.001" : fmt(p, 3)

# ╔═╡ 5195d130-051e-5595-9b61-aab379b3ec3d
"Format a coefficient with decimals that suit its size."
fmt_coef(x) = fmt(x, abs(x) < 1 ? 3 : abs(x) < 100 ? 2 : 1)

# ╔═╡ 3667542c-4d87-5918-911b-06e44bd847bf
# R-style p-value and significance stars, used by the summary/anova printouts
begin
	rpval(p) = p < 2e-16 ? "<2e-16" : p < 1e-3 ? @sprintf("%.2e", p) : @sprintf("%.4f", p)
	stars(p) = p < 0.001 ? "***" : p < 0.01 ? "**" : p < 0.05 ? "*" : p < 0.1 ? "." : ""
end

# ╔═╡ 818dfb44-fce8-5db8-b1b5-a6f83edb6adc
"""
    mdtable(df; align)

Render a data frame as a Markdown table (shown in full, also in the static HTML export).
`align` has one letter per column: `l`eft, `c`entre or `r`ight.
"""
function mdtable(df::AbstractDataFrame; align = "l" * "r"^(ncol(df) - 1))
	cell(x) = replace(string(x), "|" => "\\|")
	io = IOBuffer()
	println(io, "| ", join(cell.(names(df)), " | "), " |")
	println(io, "|", join([a == 'l' ? ":---" : a == 'c' ? ":---:" : "---:" for a in align], "|"), "|")
	for r in eachrow(df)
		println(io, "| ", join((cell(x) for x in r), " | "), " |")
	end
	Markdown.parse(String(take!(io)))
end

# ╔═╡ 1303d76d-6fdf-5f8e-a2db-c8cd23f24cbd
# Days in each month by season code: code 1 starts on 1 January, so it is winter
mdtable(unstack(combine(groupby(bike, [:month, :season]), nrow => :days), :month, :season, :days; fill = 0))

# ╔═╡ 304c09d6-5c8d-5af1-ab37-b4ef2d3e4654
let
	vars = [(:cnt, "Total rentals (casual + registered)", "bikes/day"),
	        (:temp_c, "Mean air temperature", "°C"),
	        (:atemp_c, "Mean feels-like temperature", "°C"),
	        (:hum_pct, "Mean relative humidity", "%"),
	        (:wind_kmh, "Mean wind speed", "km/h")]
	mdtable(DataFrame([(Variable = "`$(v)`", Description = desc, Units = u,
	                    Mean = fmt(mean(dm[!, v]), 1), SD = fmt(std(dm[!, v]), 1),
	                    Min = fmt(minimum(dm[!, v]), 1), Max = fmt(maximum(dm[!, v]), 1))
	                   for (v, desc, u) in vars]); align = "lllrrrr")
end

# ╔═╡ 435dfd91-3d65-5ae9-85d2-bdd138fc8d19
let
	rows = DataFrame("Factor" => String[], "Level" => String[], "Days" => Int[], "Mean rentals/day" => String[])
	for (v, levs) in [(:year, ["2011", "2012"]), (:season, ["Winter", "Spring", "Summer", "Fall"]),
	                  (:daytype, ["Working day", "Weekend", "Holiday"]),
	                  (:weather, ["Clear", "Mist/cloudy", "Light rain/snow"])]
		for l in levs
			sub = dm[dm[!, v] .== l, :cnt]
			push!(rows, (string(v), l, length(sub), fmt(mean(sub), 0)))
		end
	end
	mdtable(rows; align = "llrr")
end

# ╔═╡ 91e1aa7a-14c1-5374-8241-6b04338244af
pretty_term = Dict(
	"(Intercept)"              => "(Intercept)",
	"year: 2012"               => "Year 2012 (vs 2011)",
	"season: Spring"           => "Spring (vs winter)",
	"season: Summer"           => "Summer (vs winter)",
	"season: Fall"             => "Fall (vs winter)",
	"daytype: Weekend"         => "Weekend (vs working day)",
	"daytype: Holiday"         => "Holiday (vs working day)",
	"weather: Mist/cloudy"     => "Mist/cloudy (vs clear)",
	"weather: Light rain/snow" => "Light rain/snow (vs clear)",
	"temp_c"                   => "Temperature (°C)",
	"tc"                       => "T = temperature − 20 °C",
	"tc ^ 2"                   => "T²",
	"tc ^ 3"                   => "T³",
	"hum_pct"                  => "Humidity (%)",
	"wind_kmh"                 => "Wind speed (km/h)",
)

# ╔═╡ 857c3f8d-abc6-57d3-8078-0dd96feb194b
"""
    r_summary(m; call)

Print a fitted linear model the way R's `summary(lm(...))` does.
"""
function r_summary(m; call = "")
	b, se = coef(m), stderror(m)
	df = Int(dof_residual(m)); tv = b ./ se
	pv = 2 .* ccdf.(TDist(df), abs.(tv))
	nm = coefnames(m)
	y = response(m); e = residuals(m)
	rss, tss = sum(abs2, e), sum(abs2, y .- mean(y))
	k = length(b) - 1
	F = ((tss - rss) / k) / (rss / df)
	io = IOBuffer()
	println(io, "Call:\nlm(formula = ", call, ")\n")
	println(io, "Residuals:")
	println(io, join(lpad.(["Min", "1Q", "Median", "3Q", "Max"], 9)))
	println(io, join(lpad.([@sprintf("%.1f", q) for q in quantile(e, [0, 0.25, 0.5, 0.75, 1])], 9)), "\n")
	println(io, "Coefficients:")
	w = maximum(length, nm) + 2
	println(io, rpad("", w), lpad("Estimate", 11), lpad("Std. Error", 12), lpad("t value", 9), lpad("Pr(>|t|)", 11))
	for i in eachindex(b)
		println(io, rpad(nm[i], w), lpad(@sprintf("%.3f", b[i]), 11), lpad(@sprintf("%.3f", se[i]), 12),
		        lpad(@sprintf("%.2f", tv[i]), 9), lpad(rpval(pv[i]), 11), " ", stars(pv[i]))
	end
	println(io, "---\nSignif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1\n")
	println(io, "Residual standard error: ", @sprintf("%.1f", sqrt(rss / df)), " on ", df, " degrees of freedom")
	println(io, "Multiple R-squared:  ", @sprintf("%.4f", r2(m)), ",\tAdjusted R-squared:  ", @sprintf("%.4f", adjr2(m)))
	print(io, "F-statistic: ", @sprintf("%.1f", F), " on ", k, " and ", df, " DF,  p-value: ", rpval(ccdf(FDist(k, df), F)))
	Text(String(take!(io)))
end

# ╔═╡ f2ca76cb-50ef-57b5-a2f3-2d83a1591dab
r_summary(m_slr; call = "cnt ~ temp_c, data = dm")

# ╔═╡ 8b2b4aaf-2b4e-58fd-8cf0-ff0ef19b8005
r_summary(m_base; call = "cnt ~ year + season + daytype + weather + temp_c + hum_pct + wind_kmh")

# ╔═╡ c680c62f-b073-5bb9-b152-e084fa180d01
r_summary(m_full; call = "cnt ~ year + season + month + daytype + weather + tc + tc^2 + tc^3 + atemp_c + hum_pct + wind_kmh")

# ╔═╡ 683c0cec-1766-52d0-8c92-f66902c5fc10
"""
    anova_text(models; labels)

Sequential F-tests for nested linear models, printed like R's `anova(m1, m2, ...)`.
Each test uses the residual mean square of the largest model.
"""
function anova_text(models; labels)
	rss = deviance.(models); rdf = Int.(dof_residual.(models))
	big = argmin(rdf)
	scale = rss[big] / rdf[big]
	io = IOBuffer()
	println(io, "Analysis of Variance Table\n")
	for (i, l) in enumerate(labels)
		println(io, "Model ", i, ": ", l)
	end
	println(io, "  ", lpad("Res.Df", 7), lpad("RSS", 13), lpad("Df", 4), lpad("Sum of Sq", 13), lpad("F", 9), lpad("Pr(>F)", 11))
	for i in eachindex(models)
		print(io, rpad(i, 2), lpad(rdf[i], 7), lpad(@sprintf("%.0f", rss[i]), 13))
		if i > 1
			d = rdf[i - 1] - rdf[i]; ss = rss[i - 1] - rss[i]
			F = (ss / d) / scale; p = ccdf(FDist(d, rdf[big]), F)
			print(io, lpad(d, 4), lpad(@sprintf("%.0f", ss), 13), lpad(@sprintf("%.2f", F), 9), lpad(rpval(p), 11), " ", stars(p))
		end
		println(io)
	end
	print(io, "---\nSignif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1")
	Text(String(take!(io)))
end

# ╔═╡ c136ce26-4cd2-501a-b0e3-eb5b07da829f
anova_text([m_base, m_quad, m_cubic, m_quart];
	labels = ["cnt ~ year + season + daytype + weather + temp_c + hum_pct + wind_kmh",
	          "cnt ~ year + season + daytype + weather + tc + tc^2 + hum_pct + wind_kmh",
	          "cnt ~ year + season + daytype + weather + tc + tc^2 + tc^3 + hum_pct + wind_kmh",
	          "cnt ~ year + season + daytype + weather + tc + tc^2 + tc^3 + tc^4 + hum_pct + wind_kmh"])

# ╔═╡ 0143083b-8b8d-524d-9ca4-250b5c3fb636
"F-test of a reduced model against a larger model that contains it."
function nested_ftest(reduced, full)
	rss_r, rss_f = deviance(reduced), deviance(full)
	df1 = Int(dof_residual(reduced) - dof_residual(full)); df2 = Int(dof_residual(full))
	F = ((rss_r - rss_f) / df1) / (rss_f / df2)
	(F = F, df1 = df1, df2 = df2, p = ccdf(FDist(df1, df2), F), rss_r = rss_r, rss_f = rss_f)
end

# ╔═╡ 22a123ef-912a-5eea-921b-722060276e33
begin
	ftest_curv = nested_ftest(m_base, m_cubic)    # H0: β(T²) = β(T³) = 0
	ftest_quart = nested_ftest(m_cubic, m_quart)  # H0: β(T⁴) = 0
end;

# ╔═╡ de74dd97-6b0c-5e00-b81e-9c68d07d26a8
Markdown.parse("""
**Hypothesis test: linear vs. cubic temperature.**

* ``H_0: \\beta_{T^2} = \\beta_{T^3} = 0`` (the temperature effect is linear) vs. ``H_a``: at least one of the two coefficients is not 0.
* ``F = \\dfrac{(\\text{RSS}_{\\text{reduced}} - \\text{RSS}_{\\text{full}})/2}{\\text{RSS}_{\\text{full}}/(n - p)}`` = ($(fmt(ftest_curv.rss_r, 0)) − $(fmt(ftest_curv.rss_f, 0))) / 2 ÷ ($(fmt(ftest_curv.rss_f, 0)) / $(ftest_curv.df2)) = $(fmt(ftest_curv.F, 1)) on 2 and $(ftest_curv.df2) df, ``p`` $(fmt_p(ftest_curv.p)).
* Because ``p < 0.05`` we reject ``H_0``: holding the other predictors constant, the effect of temperature is curved.

The quadratic and cubic terms are each highly significant, while a quartic term adds nothing (``p`` = $(fmt(ftest_quart.p, 2))). The cubic is the lowest-degree polynomial that captures the shape, and it also has the lowest AIC, BIC and 10-fold cross-validated prediction error of the four:
""")

# ╔═╡ 7b5d9cc3-59b1-533a-b201-3147f3b38662
"10-fold cross-validated root-mean-squared prediction error of formula `f`."
function cv_rmse(f, data; k = 10, seed = 2026, contrasts = coding)
	folds = shuffle(Xoshiro(seed), mod1.(1:nrow(data), k))
	sse = 0.0
	for j in 1:k
		train, test = data[folds .!= j, :], data[folds .== j, :]
		mj = lm(f, train; contrasts)
		sse += sum(abs2, test.cnt .- predict(mj, test))
	end
	sqrt(sse / nrow(data))
end

# ╔═╡ 0fc8bbc0-a2f8-5a5e-a677-0e23b60ff107
let
	rows = map(temp_formulas) do (name, f)
		m = lm(f, dm; contrasts = coding)
		(name, length(coef(m)), fmt(r2(m), 4), fmt(adjr2(m), 4), fmt(sqrt(deviance(m) / dof_residual(m)), 1),
		 fmt(aic(m), 1), fmt(bic(m), 1), fmt(cv_rmse(f, dm), 1))
	end
	mdtable(DataFrame([n => getindex.(rows, i) for (i, n) in enumerate(
		["Temperature term", "Parameters", "R²", "Adj. R²", "σ̂", "AIC", "BIC", "10-fold CV RMSE"])]))
end

# ╔═╡ d16c3251-6dec-54f3-84e3-5cc5b1947163
"""
    gvif_table(m; merge = [])

Generalized variance inflation factors (Fox & Monette, 1992) for each term of `m`,
like `car::vif()`. For a one-column term the GVIF equals the ordinary VIF.
`merge` pools several terms, e.g. `[["tc", "tc ^ 2", "tc ^ 3"] => "poly(tc, 3)"]`.
"""
function gvif_table(m; merge = Pair{Vector{String}, String}[])
	X = modelmatrix(m)
	a = StatsModels.asgn(formula(m))
	tnames = [replace(string(t), r"^:\((.*)\)$" => s"\1") for t in formula(m).rhs.terms]   # ":(tc ^ 2)" → "tc ^ 2"
	cols = findall(>(1), a)                       # drop the intercept (term 1)
	labels = tnames[a[cols]]
	for (group, newname) in merge
		labels = [l in group ? newname : l for l in labels]
	end
	R = cor(X[:, cols]); dR = det(R)
	rows = map(unique(labels)) do l
		J = findall(==(l), labels); K = findall(!=(l), labels)
		g = det(R[J, J]) * det(R[K, K]) / dR
		(Term = l, Df = length(J), GVIF = g, GVIF_adj = g^(1 / (2 * length(J))))
	end
	DataFrame(rows)
end

# ╔═╡ 3f0f5d24-c311-55ea-8c66-77a1594ef1cf
vif_full = gvif_table(m_full);

# ╔═╡ 0dc17052-2e7f-5d2f-bcf6-61970557a088
mdtable(DataFrame("Term" => vif_full.Term, "Df" => vif_full.Df, "GVIF" => fmt.(vif_full.GVIF, 2),
                  "GVIF^(1/(2·Df))" => fmt.(vif_full.GVIF_adj, 2)))

# ╔═╡ 7578107e-672a-57ef-94df-a931f46ae9ca
collinearity = let m = m_full, nm = coefnames(m_full)
	pv = 2 .* ccdf.(TDist(dof_residual(m)), abs.(coef(m) ./ stderror(m)))
	month_rows = findall(startswith("month"), nm)
	(se_tc_cubic = stderror(m_cubic)[findfirst(==("tc"), coefnames(m_cubic))],
	 se_tc_full = stderror(m)[findfirst(==("tc"), nm)],
	 p_atemp = pv[findfirst(==("atemp_c"), nm)],
	 n_month_sig = count(<(0.05), pv[month_rows]),
	 vif_tc = vif_full.GVIF[findfirst(==("tc"), vif_full.Term)],
	 vif_atemp = vif_full.GVIF[findfirst(==("atemp_c"), vif_full.Term)],
	 gvif_month = vif_full.GVIF[findfirst(==("month"), vif_full.Term)],
	 r_temp_atemp = cor(dm.temp_c, dm.atemp_c))
end

# ╔═╡ 35d5f8d9-8e08-5c20-a3a2-c4b41a315ca1
Markdown.parse("""
**How the problem shows up.**

1. **The summary block.** Compared with the cubic model of Section 4, the standard error of the linear temperature term jumps from $(fmt(collinearity.se_tc_cubic, 1)) to $(fmt(collinearity.se_tc_full, 1)). `atemp_c` is not significant (``p`` = $(fmt(collinearity.p_atemp, 2))) even though feels-like temperature obviously matters, and $(collinearity.n_month_sig == 0 ? "none" : string(collinearity.n_month_sig)) of the 11 month dummies $(collinearity.n_month_sig == 1 ? "is" : "are") significant at the 5 % level even though season and temperature clearly are. Large standard errors on predictors that should matter are the classic symptom of predictors that carry the same information.
2. **The VIFs.** The variance inflation factor of predictor ``j`` is ``\\text{VIF}_j = 1/(1 - R_j^2)``, where ``R_j^2`` is the ``R^2`` from regressing ``x_j`` on all the other predictors. It is the factor by which ``\\text{Var}(\\hat\\beta_j)`` is inflated compared with uncorrelated predictors, and values above 10 (above 5 for some authors) signal a problem. For factors with several dummies the table reports the generalized VIF (GVIF; Fox & Monette, 1992) and ``\\text{GVIF}^{1/(2\\,df)}``, which is on the scale of ``\\sqrt{\\text{VIF}}``. Here `tc` has a VIF of $(fmt(collinearity.vif_tc, 1)) and `atemp_c` $(fmt(collinearity.vif_atemp, 1)): the two temperatures are nearly the same variable (``r`` = $(fmt(collinearity.r_temp_atemp, 3))). Month (GVIF = $(fmt(collinearity.gvif_month, 0))) largely repeats season.

The cure is to keep only one variable from each redundant group. Backward selection, next, makes that choice by AIC and BIC.
""")

# ╔═╡ 1e05a5cb-5244-507a-88ac-35c5ac0d3c79
"""
    fit_terms(names; data = dm)

Fit `cnt ~ <terms>` where each name refers to an entry of `selection_terms`.
"""
function fit_terms(names; data = dm)
	lookup = Dict(selection_terms)
	pieces = reduce(vcat, [collect(lookup[n] isa Tuple ? lookup[n] : (lookup[n],)) for n in names])
	lm(term(:cnt) ~ foldl(+, pieces), data; contrasts = coding)
end

# ╔═╡ 3fcb3680-3d74-5915-a5ee-07affeacf74b
"""
    backward_step(names, k; data = dm)

Backward elimination like R's `step(direction = "backward", k = k)`: at each step drop the
term whose removal gives the lowest ``n \\log(\\text{RSS}/n) + k\\,p``; stop when no removal helps.
Returns the selected terms, the dropped terms (in order) and a printed trace.
"""
function backward_step(names, k; data = dm)
	current = collect(names); dropped = String[]
	n = nrow(data)
	crit(m) = n * log(deviance(m) / n) + k * length(coef(m))
	label = k == 2 ? "AIC" : "BIC"
	io = IOBuffer()
	step_no = 0
	while true
		m = fit_terms(current; data)
		base = crit(m)
		println(io, step_no == 0 ? "Start:  " : "Step:  ", label, "=", @sprintf("%.2f", base))
		println(io, "cnt ~ ", join(current, " + "), "\n")
		rows = map(current) do t
			mt = fit_terms(setdiff(current, [t]); data)
			(name = "- " * t, df = length(coef(m)) - length(coef(mt)), ss = deviance(mt) - deviance(m),
			 rss = deviance(mt), crit = crit(mt))
		end
		push!(rows, (name = "<none>", df = 0, ss = 0.0, rss = deviance(m), crit = base))
		sort!(rows; by = r -> r.crit)
		println(io, rpad("", 15), lpad("Df", 4), lpad("Sum of Sq", 13), lpad("RSS", 13), lpad(label, 10))
		for r in rows
			none = r.name == "<none>"
			println(io, rpad(r.name, 15), lpad(none ? "" : string(r.df), 4), lpad(none ? "" : @sprintf("%.0f", r.ss), 13),
			        lpad(@sprintf("%.0f", r.rss), 13), lpad(@sprintf("%.2f", r.crit), 10))
		end
		println(io)
		rows[1].name == "<none>" && break
		t = rows[1].name[3:end]
		push!(dropped, t); current = setdiff(current, [t]); step_no += 1
	end
	(selected = current, dropped = dropped, trace = Text(rstrip(String(take!(io)))))
end

# ╔═╡ 390b045a-8150-59c7-baf4-fb500b860fdd
step_aic = backward_step(first.(selection_terms), 2);

# ╔═╡ 3b7b75c9-7789-5b44-96d8-b8b604b38206
step_aic.trace

# ╔═╡ 3e6ae508-0c3b-547c-9a55-1ed68fd25e60
m_final = fit_terms(step_aic.selected);

# ╔═╡ fe727064-54f8-5036-97d2-75616b81927d
r_summary(m_final; call = "cnt ~ year + season + daytype + weather + tc + tc^2 + tc^3 + hum_pct + wind_kmh")

# ╔═╡ 55251e43-b715-5145-aa8a-b23098e32718
let X = modelmatrix(m_final), y = response(m_final)
	β̂ = (X' * X) \ (X' * y)
	n, p = size(X)
	(n = n, p = p, max_abs_difference_from_GLM = maximum(abs.(β̂ .- coef(m_final))),
	 σ̂ = sqrt(sum(abs2, y - X * β̂) / (n - p)))
end

# ╔═╡ 93a20dce-e811-5e4e-97d4-354996878eb4
Markdown.parse("""
## 7 · Inference with the final model *(Problems 1–2)*

### 7.1 Coefficients and 95 % confidence intervals

Each interval is ``\\hat\\beta_j \\pm t_{0.975,\\,n-p}\\,\\text{SE}(\\hat\\beta_j)``, with ``t_{0.975}`` = $(fmt(quantile(TDist(dof_residual(m_final)), 0.975), 4)) on ``n - p`` = $(Int(dof_residual(m_final))) degrees of freedom. Every slope is interpreted *holding the other predictors constant*.
""")

# ╔═╡ 858b2fe4-8892-5aa3-a845-6cf3b98858fe
curvature_check = let m = m_final
	m_sq = lm(@formula(cnt ~ year + season + daytype + weather + tc + tc^2 + tc^3 + hum_pct + hum_pct^2 + wind_kmh + wind_kmh^2),
	          dm; contrasts = coding)
	merge(nested_ftest(m, m_sq), (r2_gain = r2(m_sq) - r2(m), aic_drop = aic(m) - aic(m_sq)))
end

# ╔═╡ c42c9e27-18a0-5873-bd42-c7709a75bf6e
Markdown.parse("""
Adding squared humidity and wind terms is statistically detectable (``F`` = $(fmt(curvature_check.F, 2)) on $(curvature_check.df1) and $(curvature_check.df2) df, ``p`` $(fmt_p(curvature_check.p))), but it raises ``R^2`` by only $(fmt(curvature_check.r2_gain, 3)). The baseline therefore keeps the simpler linear terms, whose coefficients are directly interpretable, and the linearity assumption is reasonable.

### 8.2 Constant variance
""")

# ╔═╡ 9385f2bb-02d5-5601-b607-21ab83cbc7af
low_end = let e = residuals(m_final), ŷ = fitted(m_final)
	(n = count(<(1000), ŷ), mean_resid = mean(e[ŷ .< 1000]), n_negative = count(<(0), ŷ))
end

# ╔═╡ 03c595c5-a8c8-59c7-a678-23ec0f6c7ca8
spread = let e = residuals(m_final), ŷ = fitted(m_final)
	q = quantile(ŷ, [1 / 3, 2 / 3])
	third = [y < q[1] ? 1 : y < q[2] ? 2 : 3 for y in ŷ]
	(sd_thirds = [std(e[third .== k]) for k in 1:3],
	 sd_2011 = std(e[dm.year .== "2011"]), sd_2012 = std(e[dm.year .== "2012"]))
end

# ╔═╡ 2a26b984-1664-5c18-9897-d084443069a5
let g = gvif_table(m_final; merge = [["tc", "tc ^ 2", "tc ^ 3"] => "poly(tc, 3)"])
	mdtable(DataFrame("Term" => g.Term, "Df" => g.Df, "GVIF" => fmt.(g.GVIF, 2), "GVIF^(1/(2·Df))" => fmt.(g.GVIF_adj, 2)))
end

# ╔═╡ 02b8eb52-3091-56c9-baed-0163c38821f4
m_no_sandy = fit_terms(step_aic.selected; data = filter(r -> !(r.date in (Date(2012, 10, 29), Date(2012, 10, 30))), dm));

# ╔═╡ 22039358-cdb9-591a-9886-9b4f9246dd14
mdtable(DataFrame("Term" => [get(pretty_term, t, t) for t in coefnames(m_final)],
                  "All days" => fmt_coef.(coef(m_final)), "Without Sandy days" => fmt_coef.(coef(m_no_sandy)),
                  "Change (%)" => fmt.(100 .* (coef(m_no_sandy) .- coef(m_final)) ./ abs.(coef(m_final)), 1)))

# ╔═╡ 178c89a9-f37b-56e3-8d9d-de4a8e579338
step_bic = backward_step(first.(selection_terms), log(nrow(dm)));

# ╔═╡ b329aad0-642b-5ddf-bdbd-5518de93cce0
step_bic.trace

# ╔═╡ 372cb156-fe68-5b22-9bbe-265d08a201a7
bic_daytype_margin = let n = nrow(dm), k = log(nrow(dm))
	crit(m) = n * log(deviance(m) / n) + k * length(coef(m))
	crit(fit_terms(setdiff(step_bic.selected, ["daytype"]))) - crit(fit_terms(step_bic.selected))
end

# ╔═╡ 87c1d7e0-3d8b-5233-aebd-a8cf86d7054d
Markdown.parse("""
**(a) Terms eliminated by backward AIC, in order:** $(join(["$(i). `$(t)`" for (i, t) in enumerate(step_aic.dropped)], ", ")). After that, no deletion lowers AIC.

**(b) Backward BIC.** BIC charges ``\\log n`` = $(fmt(log(nrow(dm)), 2)) per parameter instead of 2, so it penalizes extra terms more heavily and can only end with the same number of terms as AIC or fewer. Here it drops the same $(length(step_bic.dropped)) terms ($(join("`" .* step_bic.dropped .* "`", ", "))) and $(step_bic.selected == step_aic.selected ? "selects the same model" : "selects a smaller model"). Day type is the closest call: removing it raises BIC by only $(fmt(bic_daytype_margin, 1)).

### 6.1 The final model

$(step_bic.selected == step_aic.selected ? "Both criteria select" : "AIC selects") the cubic model of Section 4. With ``T_i`` = temperature − 20 °C,

```math
\\begin{aligned}
Y_i = {} & \\beta_0 + \\beta_1\\,\\text{Yr2012}_i + \\beta_2\\,\\text{Spring}_i + \\beta_3\\,\\text{Summer}_i + \\beta_4\\,\\text{Fall}_i + \\beta_5\\,\\text{Weekend}_i + \\beta_6\\,\\text{Holiday}_i + \\beta_7\\,\\text{Mist}_i + \\beta_8\\,\\text{RainSnow}_i \\\\
& + \\beta_9\\,T_i + \\beta_{10}\\,T_i^2 + \\beta_{11}\\,T_i^3 + \\beta_{12}\\,H_i + \\beta_{13}\\,W_i + \\varepsilon_i,
\\qquad \\varepsilon_i \\overset{\\text{iid}}{\\sim} N(0, \\sigma^2).
\\end{aligned}
```
""")

# ╔═╡ 82701de8-7b3d-55a7-b463-125483ad7e5c
"""
    drop1_display(names)

F-test for dropping each term of the model `cnt ~ names` (like R's `drop1(m, test = "F")`).
"""
function drop1_display(names)
	m = fit_terms(names)
	df_res = dof_residual(m); mse = deviance(m) / df_res
	rows = map(names) do t
		mt = fit_terms(setdiff(names, [t]))
		d = length(coef(m)) - length(coef(mt))
		F = ((deviance(mt) - deviance(m)) / d) / mse
		(t, d, fmt(deviance(mt) - deviance(m), 0), fmt(F, 2), pstr(ccdf(FDist(d, df_res), F)))
	end
	mdtable(DataFrame([n => getindex.(rows, i) for (i, n) in enumerate(["Term dropped", "Df", "Sum of Sq", "F", "p"])]))
end

# ╔═╡ fea21b6a-48f9-54ed-86d6-7c94d4ca2423
drop1_display(step_aic.selected)

# ╔═╡ e3860fe1-35a6-52b7-a265-61a04c1caecd
"Coefficient table with t-based confidence intervals (rendered as Markdown)."
function coef_display(m; level = 0.95)
	df = dof_residual(m); tq = quantile(TDist(df), (1 + level) / 2)
	b, se = coef(m), stderror(m); t = b ./ se
	p = 2 .* ccdf.(TDist(df), abs.(t))
	mdtable(DataFrame(
		"Term" => [get(pretty_term, n, n) for n in coefnames(m)],
		"Estimate" => fmt_coef.(b), "SE" => fmt_coef.(se), "t" => fmt.(t, 2), "p" => pstr.(p),
		"$(round(Int, 100level)) % CI" => string.("(", fmt_coef.(b .- tq .* se), ", ", fmt_coef.(b .+ tq .* se), ")")))
end

# ╔═╡ 77017bd9-3dd7-5844-be4c-11b4bf4976ac
coef_display(m_final)

# ╔═╡ 206a98b3-cc43-5051-81b6-c0f6243e4ebe
"Estimate, SE and t-based CI of every coefficient, keyed by coefficient name."
function coef_ci(m; level = 0.95)
	tq = quantile(TDist(dof_residual(m)), (1 + level) / 2)
	Dict(n => (b = b, se = s, lo = b - tq * s, hi = b + tq * s) for (n, b, s) in zip(coefnames(m), coef(m), stderror(m)))
end

# ╔═╡ fd92b114-882b-5d58-b796-65f16b7ed036
"Two-sided t-test of H₀: β = 0 for the coefficient named `name`."
function coef_ttest(m, name; level = 0.95)
	i = findfirst(==(name), coefnames(m))
	b, se = coef(m)[i], stderror(m)[i]; df = Int(dof_residual(m))
	tq = quantile(TDist(df), (1 + level) / 2)
	(b = b, se = se, t = b / se, df = df, p = 2 * ccdf(TDist(df), abs(b / se)), lo = b - tq * se, hi = b + tq * se)
end

# ╔═╡ 079e994d-5d6d-58c9-8c86-f7ff0061857d
begin
	ttest_weekend = coef_ttest(m_final, "daytype: Weekend")
	ttest_holiday = coef_ttest(m_final, "daytype: Holiday")
end;

# ╔═╡ 644ef682-72a7-5f5d-8d69-0f5736c00458
Markdown.parse("""
**Weekend vs. working day.**

* ``H_0: \\beta_{\\text{Weekend}} = 0`` vs. ``H_a: \\beta_{\\text{Weekend}} \\neq 0``.
* ``t = \\hat\\beta / \\text{SE}`` = $(fmt(ttest_weekend.b, 1)) / $(fmt(ttest_weekend.se, 1)) = $(fmt(ttest_weekend.t, 2)) on $(ttest_weekend.df) df, ``p`` $(fmt_p(ttest_weekend.p)).
* Since ``p`` $(ttest_weekend.p < 0.05 ? "< 0.05, we reject" : "> 0.05, we fail to reject") ``H_0``. $(ttest_weekend.p < 0.05 ? "Weekends differ from working days" : "There is not sufficient evidence that weekends differ from working days") in mean daily rentals when year, season, weather, temperature, humidity and wind are held constant.

**Holiday vs. working day.**

* ``H_0: \\beta_{\\text{Holiday}} = 0`` vs. ``H_a: \\beta_{\\text{Holiday}} \\neq 0``.
* ``t`` = $(fmt(ttest_holiday.b, 1)) / $(fmt(ttest_holiday.se, 1)) = $(fmt(ttest_holiday.t, 2)) on $(ttest_holiday.df) df, ``p`` $(fmt_p(ttest_holiday.p)).
* Since ``p`` $(ttest_holiday.p < 0.05 ? "< 0.05, we reject" : "> 0.05, we fail to reject") ``H_0``. Holding the other predictors constant, a holiday averages about $(fmt(-ttest_holiday.b, 0)) fewer rentals than a working day (95 % CI $(fmt(-ttest_holiday.hi, 0)) to $(fmt(-ttest_holiday.lo, 0)) fewer). Whether this gap depends on temperature is the M3 question.

### 7.3 Term-by-term ``F``-tests

Dropping one term at a time (R's `drop1(model, test = "F")`) tests each factor and the temperature polynomial as a whole:
""")

# ╔═╡ 1c616f39-34a0-5edb-afa8-ad0b5422e1f4
"""
    predict_day(m, data, day)

Prediction, residual, and 95 % confidence and prediction intervals for one observed day,
using ``x_0^\\top (X^\\top X)^{-1} x_0``.
"""
function predict_day(m, data, day::Date; level = 0.95)
	i = findfirst(==(day), data.date)
	X = modelmatrix(m); x0 = X[i, :]
	df = dof_residual(m); σ = sqrt(deviance(m) / df)
	h0 = dot(x0, (X' * X) \ x0)
	ŷ = dot(x0, coef(m)); y = response(m)[i]
	tq = quantile(TDist(df), (1 + level) / 2)
	se_mean, se_pred = σ * sqrt(h0), σ * sqrt(1 + h0)
	(date = day, y = y, fit = ŷ, resid = y - ŷ, h0 = h0, σ = σ, tcrit = tq, df = Int(df),
	 se_mean = se_mean, se_pred = se_pred,
	 ci = (ŷ - tq * se_mean, ŷ + tq * se_mean), pi = (ŷ - tq * se_pred, ŷ + tq * se_pred),
	 temp = data.temp_c[i], hum = data.hum_pct[i], wind = data.wind_kmh[i],
	 weather = data.weather[i], daytype = data.daytype[i])
end

# ╔═╡ bb498d73-0573-5b7f-b301-70b8689c29be
tg = predict_day(m_final, dm, Date(2012, 11, 22))

# ╔═╡ c966558b-a497-5d8e-a5f4-446e97ca4fcc
j4 = predict_day(m_final, dm, Date(2011, 7, 4))

# ╔═╡ 265196b7-2ab3-53a9-adca-d6742640bcad
Markdown.parse("""
### 7.4 Prediction, residual and intervals for one day *(Problems 2b–2c)*

**Thanksgiving 2012** (Thursday 22 November 2012) was a $(lowercase(tg.weather)) holiday in the fall of 2012 with a mean temperature of $(fmt(tg.temp, 1)) °C, $(fmt(tg.hum, 1)) % humidity and $(fmt(tg.wind, 1)) km/h of wind.

* **Prediction.** ``\\hat y_0 = x_0^\\top \\hat\\beta`` = $(fmt(tg.fit, 0)) rentals.
* **Residual.** ``y_0 - \\hat y_0`` = $(fmt(tg.y, 0)) − $(fmt(tg.fit, 0)) = $(fmt(tg.resid, 0)): the model *over*-estimates Thanksgiving by about $(fmt(abs(tg.resid), 0)) rentals.
* **95 % prediction interval for a new day** with the same predictors. Here ``x_0^\\top (X^\\top X)^{-1} x_0`` = $(fmt(tg.h0, 4)), so ``\\text{SE}_{\\text{pred}} = \\hat\\sigma \\sqrt{1 + x_0^\\top (X^\\top X)^{-1} x_0}`` = $(fmt(tg.σ, 1)) × √(1 + $(fmt(tg.h0, 4))) = $(fmt(tg.se_pred, 1)). With ``t_{0.975}`` = $(fmt(tg.tcrit, 4)) on $(tg.df) df, the interval is $(fmt(tg.fit, 0)) ± $(fmt(tg.tcrit, 4)) × $(fmt(tg.se_pred, 1)) = ($(fmt(tg.pi[1], 0)), $(fmt(tg.pi[2], 0))).
* **95 % confidence interval for the mean** response at ``x_0`` uses ``\\hat\\sigma \\sqrt{x_0^\\top (X^\\top X)^{-1} x_0}`` = $(fmt(tg.se_mean, 1)) instead and gives ($(fmt(tg.ci[1], 0)), $(fmt(tg.ci[2], 0))). It is much narrower because it leaves out the day-to-day error ``\\varepsilon_0``.

The observed $(fmt(tg.y, 0)) rentals fall far below even the prediction interval, so Thanksgiving behaves very differently from an average holiday. **Independence Day 2011**, a warm holiday, shows the opposite pattern: predicted $(fmt(j4.fit, 0)), observed $(fmt(j4.y, 0)), residual +$(fmt(j4.resid, 0)). A cold holiday that is over-predicted and a warm holiday that is under-predicted suggest that the holiday effect depends on temperature. That is the interaction M3 will test.
""")

# ╔═╡ 534d78c1-20ba-5c47-99c9-4eb9ccba4ec9
"""
    lm_diagnostics(m, data)

Fitted values, residuals, standardized and studentized residuals, leverage and Cook's distance.
"""
function lm_diagnostics(m, data)
	X = modelmatrix(m); e = residuals(m)
	n, p = size(X)
	C = cholesky(Symmetric(X' * X))
	h = vec(sum(abs2, X / C.U; dims = 2))                    # hᵢᵢ = xᵢ'(X'X)⁻¹xᵢ
	s2 = sum(abs2, e) / (n - p)
	r_std = e ./ sqrt.(s2 .* (1 .- h))                       # internally studentized
	s2_i = ((n - p) .* s2 .- e .^ 2 ./ (1 .- h)) ./ (n - p - 1)
	r_stu = e ./ sqrt.(s2_i .* (1 .- h))                     # externally studentized
	DataFrame(date = data.date, label = data.label, daytype = data.daytype, weather = data.weather,
	          cnt = response(m), fitted = fitted(m), resid = e, r_std = r_std, r_stu = r_stu,
	          leverage = h, cooks_d = r_std .^ 2 ./ p .* h ./ (1 .- h))
end

# ╔═╡ b28a7a1e-7604-5cd8-beec-f45d1fed301e
dx = lm_diagnostics(m_final, dm);

# ╔═╡ 3584448f-db33-501d-9d2e-aded839ec383
normality = let e = residuals(m_final)
	sw = ShapiroWilkTest(e)
	(W = sw.W, p = pvalue(sw), skewness = skewness(e), excess_kurtosis = kurtosis(e),
	 beyond_3 = count(r -> abs(r) > 3, dx.r_stu))
end

# ╔═╡ d7e240c4-43e9-5623-9c2f-c05e1632613b
influence_summary = let p = size(modelmatrix(m_final), 2), n = nrow(dx)
	high_h = dx.leverage .> 2p / n
	(p = p, n = n, h_mean = p / n, h_cut = 2p / n, n_high_h = count(high_h),
	 n_high_h_rare = count(high_h .& ((dx.weather .== "Light rain/snow") .| (dx.daytype .== "Holiday"))),
	 max_h = maximum(dx.leverage), n_cook = count(>(4 / n), dx.cooks_d), max_cook = maximum(dx.cooks_d),
	 max_cook_day = dx.date[argmax(dx.cooks_d)],
	 max_h_day = dx.date[argmax(dx.leverage)], max_h_temp = dm.temp_c[argmax(dx.leverage)],
	 max_h_rstu = dx.r_stu[argmax(dx.leverage)])
end

# ╔═╡ 123aff1a-ce1a-5c4e-abe7-4acc1e8abe67
Markdown.parse("""
The Q–Q plot is straight in the middle, but the lowest residuals fall well below the line: the residual distribution has a **heavy left tail** (skewness $(fmt(normality.skewness, 2)), excess kurtosis $(fmt(normality.excess_kurtosis, 2))). The Shapiro–Wilk test confirms the departure (``W`` = $(fmt(normality.W, 3)), ``p`` $(fmt_p(normality.p))). The tail is made up of the days the model cannot know about, such as storms and holidays like Thanksgiving: $(normality.beyond_3) days have studentized residuals beyond ±3.

With ``n`` = $(nrow(dm)), the central limit theorem keeps the ``t``-based intervals and tests for the coefficients approximately valid. Prediction intervals for single days rely directly on normal errors, so they are less trustworthy in the tails.

### 8.4 Leverage and influence

* **Leverage** ``h_{ii} = x_i^\\top (X^\\top X)^{-1} x_i`` measures how unusual a day's predictor values are. The average is ``p/n`` = $(fmt(influence_summary.h_mean, 3)), and the usual flag is ``2p/n`` = $(fmt(influence_summary.h_cut, 3)).
* **Studentized residuals** larger than about ±3 flag outliers in ``y``.
* **Cook's distance** ``D_i = \\dfrac{r_i^2}{p}\\,\\dfrac{h_{ii}}{1 - h_{ii}}`` combines the two. It measures how much all the fitted values move when day ``i`` is deleted; ``D_i > 4/n`` is a common screening flag and ``D_i > 0.5`` a serious one.
""")

# ╔═╡ 6c29df36-6f08-5490-a746-a8919f58520d
Markdown.parse("""
**Reading the plots.** $(influence_summary.n_high_h) days exceed the ``2p/n`` leverage flag, and $(influence_summary.n_high_h_rare) of them are light-rain/snow days or holidays. These are rare categories (21 days each), so each such day is necessarily far from the center of the predictor space; that is a property of the design, not an error. The highest leverage (``h`` = $(fmt(influence_summary.max_h, 3))) belongs to the coldest day in the data, $(Dates.format(influence_summary.max_h_day, "d u yyyy")) ($(fmt(influence_summary.max_h_temp, 1)) °C), where the cubic temperature terms are extreme; its studentized residual is only $(fmt(influence_summary.max_h_rstu, 2)), so it is not influential. The largest Cook's distance is $(fmt(influence_summary.max_cook, 3)) ($(Dates.format(influence_summary.max_cook_day, "d u yyyy")), Hurricane Sandy), far below 0.5, so **no single day controls the fit**. The most influential days in the table are real events (two hurricanes, both Thanksgivings, Independence Day, a snowstorm) or cold, wet days for which the model predicts a negative count. None of them is a data error, so all stay in the model. Section 8.7 checks how much the hurricane days move the estimates.

### 8.5 Independence

The days form a time series, so residuals on neighboring days may be correlated.
""")

# ╔═╡ 8f0f82d1-0133-5e92-bc63-15f82f2c3e6b
independence = let e = dx.resid[sortperm(dx.date)]
	r = autocor(e, [1, 7, 14])
	(durbin_watson = sum(abs2, diff(e)) / sum(abs2, e), lag1 = r[1], lag7 = r[2], lag14 = r[3])
end

# ╔═╡ 13e28fbf-f753-55f4-8bcf-95ab485955a4
Markdown.parse("""
The residuals are **positively autocorrelated**: the lag-1 autocorrelation is $(fmt(independence.lag1, 2)) (the dashed band is ``\\pm 1.96/\\sqrt{n}``) and the Durbin–Watson statistic is $(fmt(independence.durbin_watson, 2)), well below the value of 2 expected under independence. Smaller peaks at multiples of 7 days (lag 7: $(fmt(independence.lag7, 2)); lag 14: $(fmt(independence.lag14, 2))) point to a weekly pattern beyond the weekend/working-day split. Consecutive days share conditions the model does not see, such as multi-day weather systems, events and gradual growth in membership. The OLS estimates are still unbiased, but the usual standard errors are too small. Newey–West standard errors (8.7) correct for this.

### 8.6 Multicollinearity in the final model

With `atemp_c` and `month` removed, the generalized VIFs are small. The three temperature terms are grouped, because ``T``, ``T^2`` and ``T^3`` are correlated by construction:
""")

# ╔═╡ 6bd45608-925d-58c1-a0e5-cafe0955d309
"Koenker's studentized Breusch–Pagan test, against all regressors and against the fitted values."
function breusch_pagan(m)
	X = modelmatrix(m); u = residuals(m) .^ 2; n = length(u)
	r2_aux(Z) = 1 - sum(abs2, u - Z * (Z \ u)) / sum(abs2, u .- mean(u))
	lm_all = n * r2_aux(X); df_all = size(X, 2) - 1
	lm_fit = n * r2_aux([ones(n) fitted(m)])
	(lm_all = lm_all, df_all = df_all, p_all = ccdf(Chisq(df_all), lm_all),
	 lm_fit = lm_fit, p_fit = ccdf(Chisq(1), lm_fit))
end

# ╔═╡ 1cba0456-559b-51f2-b168-b54671242470
bp = breusch_pagan(m_final)

# ╔═╡ 0f05e29d-fa30-5e21-be0a-893cc893bf6c
Markdown.parse("""
**Reading the plots.** Over most of the range the LOESS line in the residuals-vs-fitted plot stays near zero and the vertical spread is similar: the residual SD is $(fmt(spread.sd_thirds[1], 0)), $(fmt(spread.sd_thirds[2], 0)) and $(fmt(spread.sd_thirds[3], 0)) in the lower, middle and upper thirds of the fitted values, so there is no fan shape. The exception is the **low end**. On the $(low_end.n) days with fitted values below 1,000 (cold, wet or windy days) the model under-predicts by $(fmt(low_end.mean_resid, 0)) rentals on average, and on $(low_end.n_negative) of them it predicts a *negative* number of rentals. An additive linear model cannot respect the floor at zero, and this is the clearest sign that a log-link count model (final project) will fit better. The spread also differs by **year**: SD $(fmt(spread.sd_2011, 0)) in 2011 vs. $(fmt(spread.sd_2012, 0)) in 2012. The system grew a lot between the two years, and its day-to-day noise grew with it.

**Breusch–Pagan test** (Koenker's studentized version) regresses ``e_i^2`` on the predictors and uses ``LM = n R^2_{\\text{aux}} \\sim \\chi^2_{df}`` under ``H_0``: constant variance.

* Against all predictors: ``LM`` = $(fmt(bp.lm_all, 1)) on $(bp.df_all) df, ``p`` $(fmt_p(bp.p_all)). We reject constant variance, because the variance depends on some predictors (chiefly the year).
* Against the fitted values only: ``LM`` = $(fmt(bp.lm_fit, 2)) on 1 df, ``p`` $(fmt_p(bp.p_fit)). There is no evidence that the variance grows with the mean.

So the constant-variance assumption holds roughly across fitted values but not across years. The estimates stay unbiased, but the usual standard errors can be off; Section 8.7 re-checks the inference with heteroscedasticity-robust standard errors.

### 8.3 Normality of the residuals
""")

# ╔═╡ 4a891c07-30cd-51ed-97dc-ac9eaa5f7a19
"HC3 heteroscedasticity-consistent covariance matrix of the OLS estimates."
function vcov_hc3(m)
	X = modelmatrix(m); e = residuals(m)
	XtXi = inv(cholesky(Symmetric(X' * X)))
	h = vec(sum((X * XtXi) .* X; dims = 2))
	XtXi * (X' * (X .* (e .^ 2 ./ (1 .- h) .^ 2))) * XtXi
end

# ╔═╡ 7599cc52-706c-5fde-bbda-114308464a76
"""
    vcov_newey_west(m, order; lags)

Newey–West (HAC) covariance with a Bartlett kernel; `order` puts the rows in time order.
"""
function vcov_newey_west(m, order; lags)
	X = modelmatrix(m)[order, :]; e = residuals(m)[order]
	XtXi = inv(cholesky(Symmetric(X' * X)))
	u = X .* e
	S = u' * u
	for l in 1:lags
		Γ = u[(l + 1):end, :]' * u[1:(end - l), :]
		S += (1 - l / (lags + 1)) * (Γ + Γ')
	end
	XtXi * S * XtXi
end

# ╔═╡ 591d23d4-f035-57e9-9a66-1c4b216e0234
robust = let m = m_final
	order = sortperm(dm.date)
	V_hc3, V_nw = vcov_hc3(m), vcov_newey_west(m, order; lags = nw_lags)
	b = coef(m); se_nw = sqrt.(diag(V_nw))
	DataFrame(term = coefnames(m), estimate = b, se_ols = stderror(m), se_hc3 = sqrt.(diag(V_hc3)), se_nw = se_nw,
	          p_ols = 2 .* ccdf.(TDist(dof_residual(m)), abs.(b ./ stderror(m))),
	          p_nw = 2 .* ccdf.(TDist(dof_residual(m)), abs.(b ./ se_nw)))
end;

# ╔═╡ 8c5f01cd-b1e0-5499-babb-29cefa12bea8
mdtable(DataFrame("Term" => [get(pretty_term, t, t) for t in robust.term], "Estimate" => fmt_coef.(robust.estimate),
                  "SE (OLS)" => fmt_coef.(robust.se_ols), "SE (HC3)" => fmt_coef.(robust.se_hc3),
                  "SE (Newey–West)" => fmt_coef.(robust.se_nw), "p (OLS)" => pstr.(robust.p_ols), "p (Newey–West)" => pstr.(robust.p_nw)))

# ╔═╡ f0428f99-1cc0-50b4-8712-fcecf7a0cde0
robust_changes = let r = robust[2:end, :]
	(ratio_min = minimum(r.se_nw ./ r.se_ols), ratio_max = maximum(r.se_nw ./ r.se_ols),
	 lost = r.term[(r.p_ols .< 0.05) .& (r.p_nw .>= 0.05)])
end

# ╔═╡ cfd3c36b-5c47-522f-a3c8-3c6fc989ecd6
Markdown.parse("""
The Newey–West standard errors are $(fmt(robust_changes.ratio_min, 1)) to $(fmt(robust_changes.ratio_max, 1)) times the OLS ones. $(isempty(robust_changes.lost) ? "Every coefficient that is significant with OLS standard errors stays significant at the 5 % level" : "Coefficients that lose significance at the 5 % level: " * join("`" .* robust_changes.lost .* "`", ", ") * "; all other conclusions stand").

**Hurricane Sandy.** On 29–30 October 2012 the system was nearly shut down (22 and 1,096 rentals). Refitting without those two days barely changes the estimates:
""")

# ╔═╡ 98b9ee02-e261-54e5-86fc-88180cef1f06
"""
    effect_table(m, data, var, values)

Effect display: for each value `v`, set `var = v` on every day, average the model-matrix
rows and return the predicted mean with a 95 % confidence interval.
"""
function effect_table(m, data, var::Symbol, values; level = 0.95)
	rhs = formula(m).rhs
	β, V = coef(m), vcov(m)
	tq = quantile(TDist(dof_residual(m)), (1 + level) / 2)
	rows = map(values) do v
		d = copy(data)
		d[!, var] = fill(v, nrow(d))
		x̄ = vec(mean(modelcols(rhs, d); dims = 1))
		est = dot(x̄, β); se = sqrt(x̄' * V * x̄)
		(value = v, fit = est, se = se, lower = est - tq * se, upper = est + tq * se)
	end
	DataFrame(rows)
end

# ╔═╡ 2e58cdde-e6b3-5344-a92c-4e71d3787e78
effects = let m = m_final
	grid(v, k) = collect(range(quantile(dm[!, v], 0.01), quantile(dm[!, v], 0.99); length = k))
	temp = effect_table(m, dm, :tc, grid(:tc, 80))
	temp.x = temp.value .+ 20
	hum = effect_table(m, dm, :hum_pct, grid(:hum_pct, 60))
	hum.x = hum.value
	wind = effect_table(m, dm, :wind_kmh, grid(:wind_kmh, 60))
	wind.x = wind.value
	weather = effect_table(m, dm, :weather, ["Clear", "Mist/cloudy", "Light rain/snow"])
	daytype = effect_table(m, dm, :daytype, ["Working day", "Weekend", "Holiday"])
	year = effect_table(m, dm, :year, ["2011", "2012"])
	(; temp, hum, wind, weather, daytype, year)
end;

# ╔═╡ 6cd0859e-fac1-59a6-a6ed-511e9f9a8ce7
"Slope of the cubic temperature effect (rentals per +1 °C) at each temperature, with a 95 % CI."
function temp_marginal_effects(m, temps; level = 0.95)
	nm = coefnames(m); β, V = coef(m), vcov(m)
	idx = [findfirst(==(c), nm) for c in ("tc", "tc ^ 2", "tc ^ 3")]
	tq = quantile(TDist(dof_residual(m)), (1 + level) / 2)
	rows = map(temps) do temp
		t = temp - 20
		g = zeros(length(β)); g[idx] = [1, 2t, 3t^2]
		s = dot(g, β); se = sqrt(g' * V * g)
		(temperature = temp, slope = s, lower = s - tq * se, upper = s + tq * se)
	end
	DataFrame(rows)
end

# ╔═╡ e7e18744-b85d-570e-9f26-3deeb819d163
temp_slopes = temp_marginal_effects(m_final, [0, 5, 10, 15, 20, 25, 30])

# ╔═╡ fb959d59-774a-5f92-b4ea-8857c0244794
mdtable(DataFrame("Temperature" => string.(temp_slopes.temperature, " °C"),
                  "Change in predicted rentals per +1 °C" => fmt.(temp_slopes.slope, 0),
                  "95 % CI" => string.("(", fmt.(temp_slopes.lower, 0), ", ", fmt.(temp_slopes.upper, 0), ")")))

# ╔═╡ db2eb977-c594-57ef-8048-82771ef025bd
"Temperature (°C) at which the fitted cubic temperature effect peaks."
function temp_peak(m)
	nm = coefnames(m); β = coef(m)
	b1, b2, b3 = (β[findfirst(==(c), nm)] for c in ("tc", "tc ^ 2", "tc ^ 3"))
	roots = [(-b2 + s * sqrt(b2^2 - 3b1 * b3)) / (3b3) for s in (-1, 1)]
	20 + only(filter(t -> 2b2 + 6b3 * t < 0, roots))      # the root where the curve is concave
end

# ╔═╡ e9f21b17-e6f1-5046-92c2-5c558b143ae4
key = let m = m_final, E = effects
	ci = coef_ci(m)
	peak = temp_peak(m)
	at(t) = only(effect_table(m, dm, :tc, [t - 20]).fit)
	mild = temp_slopes.slope[5 .<= temp_slopes.temperature .<= 15]
	(peak = peak, peak_f = 32 + 9 / 5 * peak, at_peak = at(peak), at10 = at(10), at20 = at(20), at30 = at(30),
	 slope_mild_lo = minimum(mild), slope_mild_hi = maximum(mild),
	 tc = ci["tc"], hum = ci["hum_pct"], wind = ci["wind_kmh"], mist = ci["weather: Mist/cloudy"],
	 rain = ci["weather: Light rain/snow"], holiday = ci["daytype: Holiday"], weekend = ci["daytype: Weekend"],
	 year = ci["year: 2012"], fall = ci["season: Fall"])
end

# ╔═╡ 105a4a50-0a63-5c4c-8871-80b10ffb25bf
Markdown.parse("""
**1. Temperature** (``T``, ``T^2``, ``T^3`` together; panel a). Because temperature enters as a cubic, no single coefficient describes it. The linear coefficient ``\\hat\\beta_T`` = $(fmt(key.tc.b, 1)) is the slope at 20 °C (95 % CI $(fmt(key.tc.lo, 1)) to $(fmt(key.tc.hi, 1)) rentals per °C), and the table above gives the slope at other temperatures. Holding everything else constant, predicted rentals rise by about $(fmt(key.slope_mild_lo, 0))–$(fmt(key.slope_mild_hi, 0)) per extra degree between 5 °C and 15 °C, level off at a peak near $(fmt(key.peak, 1)) °C ($(fmt(key.peak_f, 0)) °F), about $(fmt(key.at_peak, 0)) rentals on an average day, and then fall. A 30 °C day is predicted to have about $(fmt(key.at_peak - key.at30, 0)) fewer rentals than a day at the peak, and a 10 °C day about $(fmt(key.at_peak - key.at10, 0)) fewer.

**2. Humidity** (``\\hat\\beta_H`` = $(fmt(key.hum.b, 1)); panel b). Each additional percentage point of relative humidity is associated with about $(fmt(-key.hum.b, 0)) fewer rentals per day (95 % CI $(fmt(-key.hum.hi, 1)) to $(fmt(-key.hum.lo, 1)) fewer), or about $(fmt(-10 * key.hum.b, 0)) fewer for a 10-point rise, holding temperature, wind, weather type and the calendar constant.

**3. Wind speed** (``\\hat\\beta_W`` = $(fmt(key.wind.b, 1)); panel c). Each additional km/h of mean wind speed is associated with about $(fmt(-key.wind.b, 0)) fewer rentals (95 % CI $(fmt(-key.wind.hi, 1)) to $(fmt(-key.wind.lo, 1)) fewer), so a day that is 10 km/h windier has about $(fmt(-10 * key.wind.b, 0)) fewer rentals.

**4. Precipitation** (``\\hat\\beta_{\\text{RainSnow}}`` = $(fmt(key.rain.b, 0)); panel d). A day with light rain or snow averages about $(fmt(-key.rain.b, 0)) fewer rentals than an otherwise identical clear day (95 % CI $(fmt(-key.rain.hi, 0)) to $(fmt(-key.rain.lo, 0)) fewer), the largest weather effect. Misty or cloudy days average about $(fmt(-key.mist.b, 0)) fewer.

**5. Holiday** (``\\hat\\beta_{\\text{Holiday}}`` = $(fmt(key.holiday.b, 0)); panel e). Holidays average about $(fmt(-key.holiday.b, 0)) fewer rentals than working days (95 % CI $(fmt(-key.holiday.hi, 0)) to $(fmt(-key.holiday.lo, 0)) fewer) after adjusting for weather, season and year, while weekends are not significantly different from working days ($(fmt(key.weekend.b, 0)), ``p`` = $(fmt(ttest_weekend.p, 2))). Holidays are the treatment for M3.

**Context: year (panel f).** The largest single effect is system growth: holding weather and calendar constant, a day in 2012 averages about $(fmt(key.year.b, 0)) more rentals than a comparable day in 2011 (95 % CI $(fmt(key.year.lo, 0)) to $(fmt(key.year.hi, 0))).
""")

# ╔═╡ 1a807fce-4535-511c-a246-06e0f8c5740a
Markdown.parse("""
## 10 · Summary and next steps

* **Model.** Starting from a simple regression on temperature (``R^2`` = $(fmt(r2(m_slr), 3))), the analysis added weather and calendar factors, a cubic temperature term (nested ``F`` = $(fmt(ftest_curv.F, 1)), ``p`` $(fmt_p(ftest_curv.p))) and, after removing the redundant `atemp_c` and `month` by backward AIC and BIC, arrived at a model with ``R^2`` = $(fmt(r2(m_final), 3)) (adjusted $(fmt(adjr2(m_final), 3))) and ``\\hat\\sigma`` = $(fmt(sqrt(deviance(m_final) / dof_residual(m_final)), 0)) rentals/day.
* **Key effects, holding the rest constant.** Rentals peak near $(fmt(key.peak, 0)) °C. They fall by about $(fmt(-10 * key.hum.b, 0)) per 10 points of humidity, by $(fmt(-10 * key.wind.b, 0)) per 10 km/h of wind and by $(fmt(-key.rain.b, 0)) on rainy or snowy days. Holidays average $(fmt(-key.holiday.b, 0)) fewer rentals than working days, and 2012 averages $(fmt(key.year.b, 0)) more than 2011.
* **Assumptions.** Linearity holds once temperature is cubic, apart from mild curvature in humidity and wind. The variance is stable across most fitted values but larger in 2012, and the model under-predicts the slowest days. The residuals have a heavy left tail from storms and holidays, and residuals on consecutive days are correlated (lag-1 ``r`` = $(fmt(independence.lag1, 2))). No day is unduly influential (max Cook's ``D`` = $(fmt(influence_summary.max_cook, 2))). Robust standard errors are larger, but the conclusions stand.
* **Limitations.** A linear model can predict *negative* rentals on cold, wet days (the smallest fitted value is $(fmt(minimum(fitted(m_final)), 0))), and the growth from 2011 to 2012 looks multiplicative rather than additive. Both point toward a Poisson or negative-binomial GLM with a log link in the final project.
* **Next (M3).** Use day type as the treatment in an ANCOVA, adjust for the weather covariates, and add a holiday × temperature interaction to test whether the holiday effect depends on temperature, as the Thanksgiving and Independence Day residuals suggest.
""")

# ╔═╡ 36774504-de25-5f18-8bb1-d7880a3f1c35
event_notes = Dict(
	Date(2011, 1, 26)  => "Snowstorm; fitted value is negative",
	Date(2011, 3, 31)  => "Cold, wet day; fitted value is negative",
	Date(2011, 7, 4)   => "Independence Day",
	Date(2011, 8, 27)  => "Hurricane Irene",
	Date(2011, 11, 24) => "Thanksgiving",
	Date(2011, 12, 26) => "Christmas (observed)",
	Date(2012, 3, 17)  => "Warm Saturday, St. Patrick's Day",
	Date(2012, 10, 29) => "Hurricane Sandy: system nearly shut down",
	Date(2012, 10, 30) => "Hurricane Sandy, second day",
	Date(2012, 11, 22) => "Thanksgiving",
	Date(2012, 11, 24) => "Thanksgiving weekend",
	Date(2012, 11, 25) => "Thanksgiving weekend",
	Date(2012, 12, 24) => "Christmas Eve",
	Date(2012, 12, 25) => "Christmas Day",
)

# ╔═╡ d859bbe4-8de5-56d5-889e-4966555a7609
influential_days = let top = first(sort(dx, :cooks_d; rev = true), 8)
	DataFrame("Date" => Dates.format.(top.date, "e d u yyyy"), "Day type" => top.daytype, "Weather" => top.weather,
	          "Rentals" => fmt.(top.cnt, 0), "Fitted" => fmt.(top.fitted, 0), "Studentized resid." => fmt.(top.r_stu, 2),
	          "Leverage" => fmt.(top.leverage, 3), "Cook's D" => fmt.(top.cooks_d, 3),
	          "What happened" => [get(event_notes, d, "") for d in top.date])
end;

# ╔═╡ 1bf27a1a-1c7b-52b5-9fe6-d6c47d3ae62b
mdtable(influential_days; align = "lllrrrrrl")

# ╔═╡ dee730ee-2889-5b4f-ae31-5622273e4bba
md"""
## Appendix C · Plot helpers

All figures use PlutoPlotly. Each panel is built from a list of traces and then laid out with `make_subplots`. Colors follow a color-blind-safe palette: blue for data, orange for smoothers and flagged points, gray for reference lines.
"""

# ╔═╡ 92e8060a-a6d5-5486-b032-d7179a07cf72
pal = (ink = "#0b0b0b", ink2 = "#52514e", muted = "#898781", grid = "#e1e0d9", axis = "#c3c2b7",
       blue = "#2a78d6", orange = "#eb6834",
       blue_pts = "rgba(42, 120, 214, 0.45)", blue_band = "rgba(42, 120, 214, 0.15)", rug = "rgba(137, 135, 129, 0.25)")

# ╔═╡ baa12b25-e765-5a2c-be56-a29f876f8a6a
"A panel: traces plus its title and axis settings, laid out later by `assemble`."
panel(traces; title = "", xtitle = "", ytitle = "", xopts = (;), yopts = (;)) =
	(traces = collect(traces), title = title, xtitle = xtitle, ytitle = ytitle, xopts = xopts, yopts = yopts)

# ╔═╡ a00d7e2c-01d4-5eee-9fd8-66c1e6389d98
"House style: white background, hairline grid, muted axes, compact legend."
function style!(fig; height = 380, legend = false)
	relayout!(fig;
		height = height, paper_bgcolor = "white", plot_bgcolor = "white",
		font = attr(family = "Inter, Helvetica Neue, Arial, sans-serif", size = 12, color = pal.ink2),
		margin = attr(l = 64, r = 16, t = legend ? 72 : 48, b = 56),
		showlegend = legend,
		legend = attr(orientation = "h", x = 0, xanchor = "left", y = 0.995, yanchor = "top", yref = "container",
		              font = attr(size = 11, color = pal.ink2), bgcolor = "rgba(0,0,0,0)"),
		hoverlabel = attr(bgcolor = "white", bordercolor = pal.axis, font = attr(size = 12, color = pal.ink)))
	L = fig.Plot.layout
	for k in collect(keys(L.fields))
		ks = string(k)
		(startswith(ks, "xaxis") || startswith(ks, "yaxis")) || continue
		for (opt, val) in (:showgrid => true, :gridcolor => pal.grid, :gridwidth => 1, :zeroline => false,
		                   :showline => true, :linecolor => pal.axis, :linewidth => 1, :ticks => "outside",
		                   :tickcolor => pal.axis, :ticklen => 4, :automargin => true,
		                   :title_font_size => 12, :title_font_color => pal.ink2, :title_standoff => 6,
		                   :tickfont_size => 11, :tickfont_color => pal.ink2)
			L[Symbol(ks, "_", opt)] = val
		end
	end
	if haskey(L.fields, :annotations)                       # subplot titles
		for a in L[:annotations]
			a[:font] = Dict(:size => 13, :color => pal.ink)
		end
	end
	fig
end

# ╔═╡ ebe45b85-07cc-5d31-bba3-7cb4d0dacd4a
"""
    assemble(panels; rows, cols, height, legend)

Lay panels out on a `rows × cols` grid (filled row by row) and apply the house style.
With `shared_ytitle = true` only the left-hand column carries a y-axis title.
"""
function assemble(panels; rows = 1, cols = length(panels), height = 380 * rows, legend = false,
                  hspace = 0.24 / cols, vspace = 0.36 / rows, shared_ytitle = false)
	# PlotlyBase reads subplot titles in column-major order, so reshape the row-major list
	titles = reshape([p.title for p in panels], rows, cols)
	fig = make_subplots(rows = rows, cols = cols, subplot_titles = titles,
	                    horizontal_spacing = hspace, vertical_spacing = vspace)
	L = fig.Plot.layout
	for (i, p) in enumerate(panels)
		r, c = fldmod1(i, cols)
		for t in p.traces
			add_trace!(fig, t; row = r, col = c)
		end
		ax = i == 1 ? "" : string(i)
		L[Symbol("xaxis", ax, "_title_text")] = p.xtitle
		L[Symbol("yaxis", ax, "_title_text")] = (shared_ytitle && c > 1) ? "" : p.ytitle
		for (k, v) in pairs(p.xopts)
			L[Symbol("xaxis", ax, "_", k)] = v
		end
		for (k, v) in pairs(p.yopts)
			L[Symbol("yaxis", ax, "_", k)] = v
		end
	end
	style!(fig; height, legend)
end

# ╔═╡ 959f7173-6ca3-5048-9175-607b888bfc62
"LOESS smoother evaluated on a grid over the range of `x`."
function loess_xy(x, y; span = 0.6, npts = 80)
	xf = Float64.(x)
	model = loess(xf, Float64.(y); span = span)
	xs = collect(range(minimum(xf), maximum(xf); length = npts))
	(x = xs, y = predict(model, xs))
end

# ╔═╡ 2c41acbd-93e5-5a01-b66f-4454b8070d88
"Horizontal reference line from `x0` to `x1` at height `y`."
hline_trace(x0, x1, y; dash = "dot", name = "Reference", legend = false) =
	scatter(x = [x0, x1], y = [y, y], mode = "lines", name = name, legendgroup = "ref", showlegend = legend,
	        line = attr(color = pal.muted, width = 1, dash = dash), hoverinfo = "skip")

# ╔═╡ 4cd4d389-28de-56f3-8569-17ab4ecd52ec
"Component-plus-residual panel with the model's component and a LOESS smoother."
function cr_panel(x, pr, comp_x, comp_y; title, xtitle, hover, legend = false, comp_name = "Model component")
	sm = loess_xy(x, pr)
	panel([
		scatter(x = x, y = pr, mode = "markers", name = "Day", legendgroup = "pts", showlegend = legend,
		        marker = attr(size = 5, color = pal.blue_pts), text = hover,
		        hovertemplate = "%{text}<br>x = %{x:.1f}<br>component + residual = %{y:,.0f}<extra></extra>"),
		scatter(x = comp_x, y = comp_y, mode = "lines", name = comp_name, legendgroup = "comp", showlegend = legend,
		        line = attr(color = pal.ink2, width = 2, dash = "dash"), hoverinfo = "skip"),
		scatter(x = sm.x, y = sm.y, mode = "lines", name = "LOESS smoother", legendgroup = "loess", showlegend = legend,
		        line = attr(color = pal.orange, width = 2), hoverinfo = "skip"),
	]; title, xtitle, ytitle = "Component + residual")
end

# ╔═╡ 61ab0fcd-5ebb-56e8-8add-ee4774067bc6
fig_cr_base = let m = m_base
	e = residuals(m)
	specs = [(:temp_c, "(a) Temperature", "Temperature (°C)"),
	         (:hum_pct, "(b) Humidity", "Relative humidity (%)"),
	         (:wind_kmh, "(c) Wind speed", "Wind speed (km/h)")]
	panels = map(enumerate(specs)) do (k, (v, ttl, lab))
		β = coef(m)[findfirst(==(string(v)), coefnames(m))]
		x = dm[!, v]
		xs = collect(range(extrema(x)...; length = 50))
		cr_panel(x, e .+ β .* (x .- mean(x)), xs, β .* (xs .- mean(x));
		         title = ttl, xtitle = lab, hover = dm.label, legend = k == 1, comp_name = "Linear fit")
	end
	assemble(panels; rows = 1, cols = 3, height = 380, legend = true, shared_ytitle = true)
end

# ╔═╡ a4ae5ec9-672e-57c8-b733-b1ced8c4040e
fig_cr_final = let m = m_final
	e = residuals(m)
	b(name) = coef(m)[findfirst(==(name), coefnames(m))]
	g(t) = b("tc") * t + b("tc ^ 2") * t^2 + b("tc ^ 3") * t^3
	gbar = mean(g.(dm.tc))
	xs = collect(range(extrema(dm.temp_c)...; length = 80))
	p1 = cr_panel(dm.temp_c, e .+ g.(dm.tc) .- gbar, xs, g.(xs .- 20) .- gbar;
	              title = "(a) Temperature (cubic)", xtitle = "Temperature (°C)", hover = dm.label,
	              legend = true, comp_name = "Fitted component")
	rest = map([(:hum_pct, "(b) Humidity", "Relative humidity (%)"), (:wind_kmh, "(c) Wind speed", "Wind speed (km/h)")]) do (v, ttl, lab)
		x = dm[!, v]; bj = b(string(v))
		xs2 = collect(range(extrema(x)...; length = 50))
		cr_panel(x, e .+ bj .* (x .- mean(x)), xs2, bj .* (xs2 .- mean(x));
		         title = ttl, xtitle = lab, hover = dm.label, comp_name = "Fitted component")
	end
	assemble([p1; rest]; rows = 1, cols = 3, height = 380, legend = true, shared_ytitle = true)
end

# ╔═╡ 5db10ec2-3cfe-5518-a382-8393eea3cd1d
"Residuals against fitted values, with a LOESS smoother."
function panel_resid_fitted(dx; title = "Residuals vs fitted", legend = false)
	sm = loess_xy(dx.fitted, dx.resid)
	panel([
		scatter(x = dx.fitted, y = dx.resid, mode = "markers", name = "Day", legendgroup = "pts", showlegend = legend,
		        marker = attr(size = 5, color = pal.blue_pts), text = dx.label,
		        hovertemplate = "%{text}<br>fitted %{x:,.0f}<br>residual %{y:,.0f}<extra></extra>"),
		hline_trace(minimum(dx.fitted), maximum(dx.fitted), 0; legend),
		scatter(x = sm.x, y = sm.y, mode = "lines", name = "LOESS smoother", legendgroup = "loess", showlegend = legend,
		        line = attr(color = pal.orange, width = 2), hoverinfo = "skip"),
	]; title, xtitle = "Fitted rentals/day", ytitle = "Residual")
end

# ╔═╡ bce6e04e-f865-5ce7-b3d6-44056a981dd6
"Scale–location plot: √|standardized residual| against fitted values."
function panel_scale_location(dx; title = "Scale–location")
	y = sqrt.(abs.(dx.r_std))
	sm = loess_xy(dx.fitted, y)
	panel([
		scatter(x = dx.fitted, y = y, mode = "markers", legendgroup = "pts", showlegend = false,
		        marker = attr(size = 5, color = pal.blue_pts), text = dx.label,
		        hovertemplate = "%{text}<br>fitted %{x:,.0f}<br>√|std. resid| %{y:.2f}<extra></extra>"),
		scatter(x = sm.x, y = sm.y, mode = "lines", legendgroup = "loess", showlegend = false,
		        line = attr(color = pal.orange, width = 2), hoverinfo = "skip"),
	]; title, xtitle = "Fitted rentals/day", ytitle = "√|standardized residual|")
end

# ╔═╡ fe299749-6fbf-5b0c-84ad-7241facf0912
fig_variance = assemble([panel_resid_fitted(dx; legend = true), panel_scale_location(dx)]; rows = 1, cols = 2, height = 400, legend = true)

# ╔═╡ 205d27f9-0d20-5af5-a5b2-20ba0c4bf88c
"Normal Q–Q plot of the studentized residuals."
function panel_qq(dx; title = "Normal Q–Q plot")
	o = sortperm(dx.r_stu); n = length(o)
	q = quantile.(Normal(), ((1:n) .- 0.5) ./ n)
	lim = [min(q[1], dx.r_stu[o[1]]), max(q[end], dx.r_stu[o[end]])]
	panel([
		scatter(x = q, y = dx.r_stu[o], mode = "markers", legendgroup = "pts", showlegend = false,
		        marker = attr(size = 5, color = pal.blue_pts), text = dx.label[o],
		        hovertemplate = "%{text}<br>theoretical %{x:.2f}<br>studentized %{y:.2f}<extra></extra>"),
		scatter(x = lim, y = lim, mode = "lines", legendgroup = "ref", showlegend = false,
		        line = attr(color = pal.muted, width = 1.5, dash = "dash"), hoverinfo = "skip"),
	]; title, xtitle = "Theoretical N(0, 1) quantile", ytitle = "Studentized residual")
end

# ╔═╡ a0317095-3a0f-57e1-b064-7d73b4f8be12
"Histogram of the studentized residuals with the N(0, 1) density."
function panel_hist(dx; title = "Distribution of studentized residuals")
	xs = collect(range(minimum(dx.r_stu) - 0.25, maximum(dx.r_stu) + 0.25; length = 200))
	panel([
		histogram(x = dx.r_stu, histnorm = "probability density", xbins = attr(size = 0.25), showlegend = false,
		          marker = attr(color = pal.blue_pts, line = attr(color = "white", width = 1)),
		          hovertemplate = "%{x}<br>density %{y:.3f}<extra></extra>"),
		scatter(x = xs, y = pdf.(Normal(), xs), mode = "lines", showlegend = false,
		        line = attr(color = pal.orange, width = 2), hoverinfo = "skip"),
	]; title, xtitle = "Studentized residual", ytitle = "Density")
end

# ╔═╡ 934bff83-0986-5c08-9ab8-a1b8a906869e
fig_normality = assemble([panel_qq(dx), panel_hist(dx)]; rows = 1, cols = 2, height = 400)

# ╔═╡ c823afbe-b119-595e-9c9a-30718077ec4c
"Studentized residuals against leverage, flagging Cook's D > 4/n and labelling the largest."
function panel_leverage(dx, p; title = "Studentized residuals vs leverage", nlabel = 3, legend = false)
	n = nrow(dx); flag = dx.cooks_d .> 4 / n
	top = sortperm(dx.cooks_d; rev = true)[1:nlabel]
	hmax = 1.05 * maximum(dx.leverage)
	ylim = [minimum(dx.r_stu) - 0.4, maximum(dx.r_stu) + 0.4]
	hov = "%{text}<br>leverage %{x:.3f}<br>studentized %{y:.2f}<br>Cook's D %{customdata:.3f}<extra></extra>"
	panel([
		scatter(x = dx.leverage[.!flag], y = dx.r_stu[.!flag], mode = "markers", name = "Day", legendgroup = "pts",
		        showlegend = false, marker = attr(size = 5, color = pal.blue_pts), text = dx.label[.!flag],
		        customdata = dx.cooks_d[.!flag], hovertemplate = hov),
		scatter(x = dx.leverage[flag], y = dx.r_stu[flag], mode = "markers", name = "Cook's D > 4/n", legendgroup = "flag",
		        showlegend = legend, marker = attr(size = 7, color = pal.orange, line = attr(color = "white", width = 1)),
		        text = dx.label[flag], customdata = dx.cooks_d[flag], hovertemplate = hov),
		scatter(x = [2p / n, 2p / n], y = ylim, mode = "lines", showlegend = false, hoverinfo = "skip",
		        line = attr(color = pal.muted, width = 1, dash = "dash")),
		hline_trace(0, hmax, 3), hline_trace(0, hmax, -3),
		scatter(x = dx.leverage[top], y = dx.r_stu[top], mode = "text", showlegend = false, hoverinfo = "skip",
		        text = "  " .* Dates.format.(dx.date[top], "d u yyyy"), textposition = "middle right",
		        textfont = attr(size = 10, color = pal.ink2), cliponaxis = false),
	]; title, xtitle = "Leverage hᵢᵢ (dashed: 2p/n)", ytitle = "Studentized residual")
end

# ╔═╡ 6e36fe37-218a-5fcb-8ff2-c520f54fa1bc
"Date axis with a tick every six months."
date_axis = (type = "date", dtick = "M6", tickformat = "%b<br>%Y", tickangle = 0)

# ╔═╡ 73a02ae8-8320-5173-b948-d57a43ad94ab
"Cook's distance for every day, in time order."
function panel_cooks_time(dx; title = "Cook's distance over time", nlabel = 3)
	n = nrow(dx); top = sortperm(dx.cooks_d; rev = true)[1:nlabel]
	panel([
		scatter(x = dx.date, y = dx.cooks_d, mode = "markers", marker = attr(size = 4, color = pal.blue_pts),
		        showlegend = false, text = dx.label, hovertemplate = "%{text}<br>Cook's D %{y:.3f}<extra></extra>"),
		hline_trace(minimum(dx.date), maximum(dx.date), 4 / n; dash = "dash"),
		scatter(x = dx.date[top], y = dx.cooks_d[top], mode = "text", showlegend = false, hoverinfo = "skip",
		        text = Dates.format.(dx.date[top], "d u yyyy") .* "  ", textposition = "middle left",
		        textfont = attr(size = 10, color = pal.ink2), cliponaxis = false),
	]; title, xtitle = "Date (dashed: 4/n)", ytitle = "Cook's distance", xopts = date_axis)
end

# ╔═╡ c08549a5-8d31-5bf5-9998-eac01a9a8fec
fig_influence = assemble([panel_leverage(dx, influence_summary.p; legend = true), panel_cooks_time(dx)];
                         rows = 1, cols = 2, height = 420, legend = true)

# ╔═╡ 0a520e4b-f714-5812-967b-b7f9c34f89ee
"Residuals in time order with a LOESS trend."
function panel_resid_time(dx; title = "Residuals over time", legend = false)
	o = sortperm(dx.date)
	t = Dates.value.(dx.date[o] .- dx.date[o[1]])
	sm = loess_xy(t, dx.resid[o]; span = 0.15, npts = 200)
	panel([
		scatter(x = dx.date[o], y = dx.resid[o], mode = "markers", legendgroup = "pts", showlegend = false,
		        marker = attr(size = 4, color = pal.blue_pts), text = dx.label[o],
		        hovertemplate = "%{text}<br>residual %{y:,.0f}<extra></extra>"),
		hline_trace(dx.date[o[1]], dx.date[o[end]], 0),
		scatter(x = dx.date[o[1]] .+ Day.(round.(Int, sm.x)), y = sm.y, mode = "lines", legendgroup = "loess",
		        showlegend = false, line = attr(color = pal.orange, width = 2), hoverinfo = "skip"),
	]; title, xtitle = "Date", ytitle = "Residual", xopts = date_axis)
end

# ╔═╡ ffff8049-1a0d-55ca-9372-57a273418367
"Autocorrelation of the residuals (in time order) with ±1.96/√n bounds."
function panel_acf(dx; title = "Residual autocorrelation", maxlag = 28)
	e = dx.resid[sortperm(dx.date)]; n = length(e)
	r = autocor(e, 1:maxlag); bound = 1.96 / sqrt(n)
	panel([
		bar(x = 1:maxlag, y = r, width = 0.4, marker = attr(color = pal.blue), showlegend = false,
		    hovertemplate = "lag %{x} days<br>r = %{y:.2f}<extra></extra>"),
		hline_trace(0.5, maxlag + 0.5, bound; dash = "dash"), hline_trace(0.5, maxlag + 0.5, -bound; dash = "dash"),
		hline_trace(0.5, maxlag + 0.5, 0; dash = "solid"),
	]; title, xtitle = "Lag (days)", ytitle = "Autocorrelation", xopts = (range = [0.3, maxlag + 0.7],))
end

# ╔═╡ f99f9b53-725c-51fb-9a60-e34f242ddd5c
fig_independence = assemble([panel_resid_time(dx; legend = true), panel_acf(dx)]; rows = 1, cols = 2, height = 400, legend = true)

# ╔═╡ a0df578d-b530-5c6c-8a80-7b62a2eb8456
fig_paper_diagnostics = assemble([
		panel_resid_fitted(dx; title = "(a) Residuals vs fitted", legend = true),
		panel_scale_location(dx; title = "(b) Scale–location"),
		panel_qq(dx; title = "(c) Normal Q–Q"),
		panel_leverage(dx, influence_summary.p; title = "(d) Residuals vs leverage", nlabel = 3, legend = true),
		panel_resid_time(dx; title = "(e) Residuals over time"),
		panel_acf(dx; title = "(f) Residual autocorrelation"),
	]; rows = 2, cols = 3, height = 680, legend = true, hspace = 0.11)

# ╔═╡ 871f95e4-b3ba-50a1-94e2-64518444a161
"Partial-effect panel for a continuous predictor: fitted curve, 95 % band and a rug of observed days."
function effect_line_panel(tab, xdata; title, xtitle, yrange, xfmt = ".1f", unit = "")
	x = tab.x
	rug = filter(v -> first(x) <= v <= last(x), xdata)
	panel([
		scatter(x = vcat(x, reverse(x)), y = vcat(tab.upper, reverse(tab.lower)), fill = "toself",
		        fillcolor = pal.blue_band, line = attr(width = 0), hoverinfo = "skip", showlegend = false),
		scatter(x = x, y = tab.fit, mode = "lines", line = attr(color = pal.blue, width = 2), showlegend = false,
		        customdata = [[l, u] for (l, u) in zip(tab.lower, tab.upper)],
		        hovertemplate = "%{x:$(xfmt)}$(unit)<br>predicted %{y:,.0f}/day<br>95% CI %{customdata[0]:,.0f} – %{customdata[1]:,.0f}<extra></extra>"),
		scatter(x = rug, y = fill(yrange[1] + 0.03 * (yrange[2] - yrange[1]), length(rug)), mode = "markers",
		        marker = attr(symbol = "line-ns-open", size = 6, color = pal.rug, line = attr(width = 1)),
		        hoverinfo = "skip", showlegend = false),
	]; title, xtitle, ytitle = "Predicted rentals/day", yopts = (range = collect(yrange),))
end

# ╔═╡ 4790e3ca-3e22-5eb3-a0eb-f2ebc5232637
"Partial-effect panel for a factor: adjusted means with 95 % error bars."
function effect_point_panel(tab; title, xtitle = "", yrange, labels = Dict{String, String}())
	panel([
		scatter(x = [get(labels, v, v) for v in tab.value], y = tab.fit, mode = "markers", showlegend = false,
		        marker = attr(size = 10, color = pal.blue, line = attr(color = "white", width = 2)),
		        error_y = attr(type = "data", symmetric = false, array = tab.upper .- tab.fit,
		                       arrayminus = tab.fit .- tab.lower, color = pal.blue, thickness = 1.5, width = 6),
		        customdata = [[l, u] for (l, u) in zip(tab.lower, tab.upper)],
		        hovertemplate = "%{x}<br>predicted %{y:,.0f}/day<br>95% CI %{customdata[0]:,.0f} – %{customdata[1]:,.0f}<extra></extra>"),
	]; title, xtitle, ytitle = "Predicted rentals/day", xopts = (type = "category", tickangle = 0), yopts = (range = collect(yrange),))
end

# ╔═╡ ea7eb588-da33-58c9-8514-431796a2cc0f
fig_effects = let E = effects
	lo = minimum(minimum(t.lower) for t in E)
	hi = maximum(maximum(t.upper) for t in E)
	yr = (500 * floor(lo / 500) - 250, 500 * ceil(hi / 500))
	assemble([
		effect_line_panel(E.temp, dm.temp_c; title = "(a) Temperature", xtitle = "Temperature (°C)", yrange = yr, xfmt = ".1f", unit = " °C"),
		effect_line_panel(E.hum, dm.hum_pct; title = "(b) Humidity", xtitle = "Relative humidity (%)", yrange = yr, xfmt = ".0f", unit = " %"),
		effect_line_panel(E.wind, dm.wind_kmh; title = "(c) Wind speed", xtitle = "Wind speed (km/h)", yrange = yr, xfmt = ".1f", unit = " km/h"),
		effect_point_panel(E.weather; title = "(d) Weather", yrange = yr,
		                   labels = Dict("Mist/cloudy" => "Mist or<br>cloudy", "Light rain/snow" => "Light rain<br>or snow")),
		effect_point_panel(E.daytype; title = "(e) Day type", yrange = yr),
		effect_point_panel(E.year; title = "(f) Year", yrange = yr),
	]; rows = 2, cols = 3, height = 680, shared_ytitle = true)
end

# ╔═╡ c1047b10-9bed-5545-99fe-7a42e22f6c78
paper_figures = [   # (file name, figure, width px, height px) for a ~5.2-inch print width
	("fig1_linearity", fig_cr_base, 700, 290),
	("fig2_diagnostics", fig_paper_diagnostics, 680, 520),
	("fig3_effects", fig_effects, 680, 520),
	("figA1_linearity_final", fig_cr_final, 700, 290),
];

# ╔═╡ b87d49db-2bb0-5cf1-b17f-b042daa26ea3
if export_figures
	let dir = mkpath(joinpath(@__DIR__, "figures"))
		PlotlyKaleido.start()
		for (name, fig, w, h) in paper_figures
			savefig(fig, joinpath(dir, name * ".png"); width = w, height = h, scale = 4)
		end
		saved = join(first.(paper_figures), ", ")
		Markdown.parse("Saved $(length(paper_figures)) figures to `figures/`: $(saved).")
	end
else
	md"*Export is off. Tick the box above to write the figures.*"
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
Downloads = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
GLM = "38e38edf-8417-5370-95a0-9cbb8c7f171a"
HypothesisTests = "09f84164-cd44-5f33-b23f-e6b0d136a0d5"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
Loess = "4345ca2d-374a-55d4-8d30-97f9976e7612"
PlotlyKaleido = "f2990250-8cf9-495f-b13a-cce12b45703c"
PlutoPlotly = "8e989ff0-3d88-8e9f-f020-2b208a939ff0"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
Printf = "de0858da-6303-5e67-8744-51eddeeeb8d7"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
StatsModels = "3eaba693-59b7-5ba5-a881-562e759f1c8d"
ZipFile = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"

[compat]
CSV = "~1.1.0"
DataFrames = "~1.8.2"
Distributions = "~0.25.131"
GLM = "~1.9.5"
HypothesisTests = "~0.12.2"
Loess = "~0.6.6"
PlotlyKaleido = "~2.3.1"
PlutoPlotly = "~0.6.6"
PlutoUI = "~0.7.83"
StatsBase = "~0.34.13"
StatsModels = "~0.7.10"
ZipFile = "~0.10.1"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.7"
manifest_format = "2.0"
project_hash = "a8bb86b9f04bf5ca63654c9a2d0e4bd762cea402"

[[deps.AbstractPlutoDingetjes]]
git-tree-sha1 = "e71ee7b4aa06b045259a7d6101e1cb45ad140bce"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.4.1"

[[deps.Accessors]]
deps = ["CompositionsBase", "ConstructionBase", "Dates", "InverseFunctions", "MacroTools"]
git-tree-sha1 = "7063ad1083578215c7c4bf410368150abe8d5524"
uuid = "7d9f7c33-5ae7-4f3b-8dc6-eff91059b697"
version = "0.1.45"

    [deps.Accessors.extensions]
    AxisKeysExt = "AxisKeys"
    IntervalSetsExt = "IntervalSets"
    LinearAlgebraExt = "LinearAlgebra"
    StaticArraysExt = "StaticArrays"
    StructArraysExt = "StructArrays"
    TestExt = "Test"
    UnitfulExt = "Unitful"

    [deps.Accessors.weakdeps]
    AxisKeys = "94b1ba4f-4ee9-5380-92f1-94cde586c3c5"
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
    StructArrays = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
    Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.AliasTables]]
deps = ["PtrArrays", "Random"]
git-tree-sha1 = "9876e1e164b144ca45e9e3198d0b689cadfed9ff"
uuid = "66dad0bd-aa9a-41b7-9441-69ab47430ed8"
version = "1.1.3"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.CSV]]
deps = ["CodecZlib", "DataStrings", "Dates", "Downloads", "Durations", "Mmap", "Parsers", "PooledArrays", "PrecompileTools", "Printf", "Tables", "Unicode"]
git-tree-sha1 = "ed05d41d96b1a815d52e9de1ef472971bc509832"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "1.1.0"

    [deps.CSV.extensions]
    CSVDataDecimalsExt = "DataDecimals"
    CSVFilePathsBaseExt = "FilePathsBase"
    CSVInlineStringsExt = "InlineStrings"

    [deps.CSV.weakdeps]
    DataDecimals = "3e2245cb-6932-498d-a7cf-39d39de8bde3"
    FilePathsBase = "48062228-2e41-5def-b9a4-89aafe57970f"
    InlineStrings = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "970758a3d591a2a5c2a907c53f2e2f8c1b1d3537"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.9"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "PrecompileTools", "Random"]
git-tree-sha1 = "b0fd3f56fa442f81e0a47815c92245acfaaa4e34"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.31.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "a7cf827a79b378a381e31e5c7feca853ec19cb94"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.12.4"
weakdeps = ["StyledStrings"]

    [deps.ColorTypes.extensions]
    StyledStringsExt = "StyledStrings"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "Requires", "Statistics", "TensorCore"]
git-tree-sha1 = "8b3b6f87ce8f65a2b4f857528fd8d70086cd72b1"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.11.0"
weakdeps = ["SpecialFunctions"]

    [deps.ColorVectorSpace.extensions]
    SpecialFunctionsExt = "SpecialFunctions"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "Reexport"]
git-tree-sha1 = "a633156e74096f90b3b5e833529292b651b5671a"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.13.3"

[[deps.Combinatorics]]
git-tree-sha1 = "c761b00e7755700f9cdf5b02039939d1359330e1"
uuid = "861a8166-3701-5b0c-9a16-15d98fcdc6aa"
version = "1.1.0"

[[deps.CommonSolve]]
deps = ["PrecompileTools"]
git-tree-sha1 = "6c389fa857f6ca5a95474b52a52023fd77f24cb7"
uuid = "38540f10-b2f7-11e9-35d8-d573e4eb0ff2"
version = "0.2.14"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "9d8a54ce4b17aa5bdce0ea5c34bc5e7c340d16ad"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.18.1"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.1+2"

[[deps.CompositionsBase]]
git-tree-sha1 = "802bb88cd69dfd1509f6670416bd4434015693ad"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.2"
weakdeps = ["InverseFunctions"]

    [deps.CompositionsBase.extensions]
    CompositionsBaseInverseFunctionsExt = "InverseFunctions"

[[deps.ConstructionBase]]
git-tree-sha1 = "b4b092499347b18a015186eae3042f72267106cb"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.6.0"

    [deps.ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseLinearAlgebraExt = "LinearAlgebra"
    ConstructionBaseStaticArraysExt = "StaticArrays"

    [deps.ConstructionBase.weakdeps]
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.Crayons]]
git-tree-sha1 = "54b76cbb40d9a0f5368c880725b2f141da77c94f"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.2.0"

[[deps.DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "DataStructures", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrecompileTools", "PrettyTables", "Printf", "Random", "Reexport", "SentinelArrays", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "5fab31e2e01e70ad66e3e24c968c264d1cf166d6"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.8.2"

[[deps.DataStrings]]
git-tree-sha1 = "b8032263d364177a0b192ea15f277df4e6ab07e2"
uuid = "48204bd6-5611-42ea-b167-fc1d713f9be2"
version = "1.1.0"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "b0bc6d2cad1fed8b7fd59a1551a991cb3d2809e6"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.6"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.Distances]]
deps = ["LinearAlgebra", "Statistics", "StatsAPI"]
git-tree-sha1 = "c7e3a542b999843086e2f29dac96a618c105be1d"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.12"

    [deps.Distances.extensions]
    DistancesChainRulesCoreExt = "ChainRulesCore"
    DistancesSparseArraysExt = "SparseArrays"

    [deps.Distances.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.Distributions]]
deps = ["AliasTables", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "Roots", "SpecialFunctions", "Statistics", "StatsAPI", "StatsBase", "StatsFuns"]
git-tree-sha1 = "a958ab3a40c755563f5e1405c0846cb0446bf19d"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.131"

    [deps.Distributions.extensions]
    DistributionsChainRulesCoreExt = "ChainRulesCore"
    DistributionsDensityInterfaceExt = "DensityInterface"
    DistributionsSparseConnectivityTracerExt = "SparseConnectivityTracer"
    DistributionsTestExt = "Test"

    [deps.Distributions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DensityInterface = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
    SparseConnectivityTracer = "9f842d2f-2579-4b1d-911e-f412cf18a3f5"
    Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.DocStringExtensions]]
git-tree-sha1 = "7442a5dfe1ebb773c29cc2962a8980f47221d76c"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.5"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.7.0"

[[deps.Durations]]
deps = ["Dates"]
git-tree-sha1 = "407b209d76168dcc4355f9dcc4d3b3aaa60dfb3e"
uuid = "41ac09f5-0a95-4810-aa18-c88bf48ee130"
version = "1.4.1"

    [deps.Durations.extensions]
    DurationsArrowExt = "Arrow"
    DurationsTimeZonesExt = "TimeZones"

    [deps.Durations.weakdeps]
    Arrow = "69666777-d1a9-59fb-9406-91d4454c9d45"
    TimeZones = "f269a46b-ccf7-5d73-abea-4c690281aa53"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FillArrays]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "417289ac840d201005d9ed16789a46defccbe36d"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "1.18.1"

    [deps.FillArrays.extensions]
    FillArraysPDMatsExt = "PDMats"
    FillArraysSparseArraysExt = "SparseArrays"
    FillArraysStaticArraysExt = "StaticArrays"
    FillArraysStatisticsExt = "Statistics"

    [deps.FillArrays.weakdeps]
    PDMats = "90014a1f-27ba-587c-ab20-58faa44d9150"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.FixedPointNumbers]]
deps = ["Random", "Statistics"]
git-tree-sha1 = "59af96b98217c6ef4ae0dfe065ac7c20831d1a84"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.6"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"
version = "1.11.0"

[[deps.GLM]]
deps = ["Distributions", "LinearAlgebra", "LogExpFunctions", "Printf", "Reexport", "SparseArrays", "SpecialFunctions", "Statistics", "StatsAPI", "StatsBase", "StatsModels"]
git-tree-sha1 = "c963639ae5b9aab54f543bdc7504f42f59880bec"
uuid = "38e38edf-8417-5370-95a0-9cbb8c7f171a"
version = "1.9.5"

[[deps.Gamma]]
deps = ["LogExpFunctions"]
git-tree-sha1 = "becc397f7cfb06e343496ae6ffb04818a851da51"
uuid = "a0844989-3bd2-4988-8bea-c9407ab0941b"
version = "1.2.0"

[[deps.HashArrayMappedTries]]
git-tree-sha1 = "2eaa69a7cab70a52b9687c8bf950a5a93ec895ae"
uuid = "076d061b-32b6-4027-95e0-9a2c6f6d7e74"
version = "0.2.0"

[[deps.HypergeometricFunctions]]
deps = ["Gamma", "LinearAlgebra"]
git-tree-sha1 = "31bb6c92405c084617facc1d7ed9eb6c402d061e"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.30"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "d1a86724f81bcd184a38fd284ce183ec067d71a0"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "1.0.0"

[[deps.HypothesisTests]]
deps = ["Combinatorics", "Distributions", "LinearAlgebra", "Printf", "Random", "Roots", "Statistics", "StatsAPI", "StatsBase", "StatsFuns"]
git-tree-sha1 = "0b7026cbe6b5380b8f8a5c2a7306363e2ebd2146"
uuid = "09f84164-cd44-5f33-b23f-e6b0d136a0d5"
version = "0.12.2"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "0ee181ec08df7d7c911901ea38baf16f755114dc"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "1.0.0"

[[deps.InlineStrings]]
git-tree-sha1 = "06b65886c7577a3784d616e29f1302c2e36e389d"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.6"

    [deps.InlineStrings.extensions]
    ArrowTypesExt = "ArrowTypes"
    ParsersExt = "Parsers"

    [deps.InlineStrings.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"
    Parsers = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.InverseFunctions]]
git-tree-sha1 = "a779299d77cd080bf77b97535acecd73e1c5e5cb"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.17"
weakdeps = ["Dates", "Test"]

    [deps.InverseFunctions.extensions]
    InverseFunctionsDatesExt = "Dates"
    InverseFunctionsTestExt = "Test"

[[deps.InvertedIndices]]
git-tree-sha1 = "6da3c4316095de0f5ee2ebd875df8721e7e0bdbe"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.1"

[[deps.IrrationalConstants]]
git-tree-sha1 = "b2d91fe939cae05960e760110b328288867b5758"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.6"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JSON]]
deps = ["Dates", "Logging", "Parsers", "PrecompileTools", "StructUtils", "UUIDs", "Unicode"]
git-tree-sha1 = "9939eb6f799a963b3392ac4a1d49d3fc0646eb80"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "1.11.0"

    [deps.JSON.extensions]
    JSONArrowExt = ["ArrowTypes"]

    [deps.JSON.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.Kaleido_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "43032da5832754f58d14a91ffbe86d5f176acda9"
uuid = "f7e6163d-2fa5-5f23-b69c-1db539e41963"
version = "0.2.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f88f3ccef05a6a72a0cf0ed417c8fd68530f4ab2"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.4.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.15.0+0"

[[deps.LibGit2]]
deps = ["LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"
version = "1.11.0"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.9.0+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "OpenSSL_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.3+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.12.0"

[[deps.Loess]]
deps = ["Distances", "LinearAlgebra", "Statistics", "StatsAPI", "StatsFuns"]
git-tree-sha1 = "aac61f60ed2b1561ae1bbef4e6d7b75c27f1f9e3"
uuid = "4345ca2d-374a-55d4-8d30-97f9976e7612"
version = "0.6.6"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "28d620bcdb37a3fb02de9f521928ee453690f414"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "1.0.3"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MIMEs]]
git-tree-sha1 = "c64d943587f7187e751162b3b84445bbbd79f691"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.1.0"

[[deps.MacroTools]]
git-tree-sha1 = "1e0228a030642014fe5cfe68c2c0a818f9e3f522"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.16"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "ec4f7fbeab05d7747bdf98eb74d130a2a2ed298d"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.2.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2025.11.4"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.3.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.29+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.7+0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.5.6+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1346c9208249809840c91b26703912dff463d335"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.6+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "94ba93778373a53bfd5a0caaf7d809c445292ff4"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.8.2"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "123266c25174ef6c8d4718920abc206452cf8de6"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.41"
weakdeps = ["StatsBase"]

    [deps.PDMats.extensions]
    StatsBaseExt = "StatsBase"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools"]
git-tree-sha1 = "663e8b48b789916221e0765393b289ca6c88f24e"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "3.0.0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "Random", "SHA", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.12.1"
weakdeps = ["REPL"]

    [deps.Pkg.extensions]
    REPLExt = "REPL"

[[deps.PlotlyBase]]
deps = ["ColorSchemes", "Colors", "Dates", "DelimitedFiles", "DocStringExtensions", "JSON", "LaTeXStrings", "Logging", "Parameters", "Pkg", "REPL", "Requires", "Statistics", "UUIDs"]
git-tree-sha1 = "6256ab3ee24ef079b3afa310593817e069925eeb"
uuid = "a03496cd-edff-5a9b-9e67-9cda94a718b5"
version = "0.8.23"

    [deps.PlotlyBase.extensions]
    DataFramesExt = "DataFrames"
    DistributionsExt = "Distributions"
    IJuliaExt = "IJulia"
    JSON3Ext = "JSON3"

    [deps.PlotlyBase.weakdeps]
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
    IJulia = "7073ff75-c697-5162-941a-fcdaad2a7d2a"
    JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"

[[deps.PlotlyKaleido]]
deps = ["Artifacts", "Base64", "JSON", "Kaleido_jll"]
git-tree-sha1 = "c7a270d11881c0709052f8e3def3d60d551e99f3"
uuid = "f2990250-8cf9-495f-b13a-cce12b45703c"
version = "2.3.1"

[[deps.PlutoPlotly]]
deps = ["AbstractPlutoDingetjes", "Artifacts", "ColorSchemes", "Colors", "Dates", "Downloads", "HypertextLiteral", "InteractiveUtils", "LaTeXStrings", "Markdown", "Pkg", "PlotlyBase", "PrecompileTools", "Reexport", "ScopedValues", "Scratch", "TOML"]
git-tree-sha1 = "2b9e3d771adfe535a4fdda855f4741fdaacd3f7f"
uuid = "8e989ff0-3d88-8e9f-f020-2b208a939ff0"
version = "0.6.6"

    [deps.PlutoPlotly.extensions]
    PlotlyKaleidoExt = "PlotlyKaleido"
    UnitfulExt = "Unitful"

    [deps.PlutoPlotly.weakdeps]
    PlotlyKaleido = "f2990250-8cf9-495f-b13a-cce12b45703c"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Downloads", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "e189d0623e7ce9c37389bac17e80aac3b0302e75"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.83"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "36d8b4b899628fb92c2749eb488d884a926614d3"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.3"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "edbeefc7a4889f528644251bdb5fc9ab5348bc2c"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.3.4"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "5005266de4bfe50e53ff44a5cb5c540b6e47a254"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.6.0"

[[deps.PrettyTables]]
deps = ["Crayons", "LaTeXStrings", "Markdown", "PrecompileTools", "Printf", "REPL", "Reexport", "StringManipulation", "StyledStrings", "Tables"]
git-tree-sha1 = "99fd8f32ab6728ff205cddd24e2d9ea6cbb498d3"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "3.5.0"

    [deps.PrettyTables.extensions]
    PrettyTablesExcelExt = "XLSX"
    PrettyTablesTypstryExt = "Typstry"
    PrettyTablesWriteDocxExt = "WriteDocx"

    [deps.PrettyTables.weakdeps]
    Typstry = "f0ed7684-a786-439e-b1e3-3b82803b501e"
    WriteDocx = "d049ceea-54ee-41d7-a26f-ba29db3b6599"
    XLSX = "fdbf4ff8-1666-58a4-91e7-1b58723a45e0"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.PtrArrays]]
git-tree-sha1 = "4fbbafbc6251b883f4d2705356f3641f3652a7fe"
uuid = "43287f4e-b6f4-7ad1-bb20-aadabca52c3d"
version = "1.4.0"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "5e8e8b0ab68215d7a2b14b9921a946fee794749e"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.11.3"

    [deps.QuadGK.extensions]
    QuadGKEnzymeExt = "Enzyme"

    [deps.QuadGK.weakdeps]
    Enzyme = "7da242da-08ed-463a-9acd-ee780be4f1d9"

[[deps.REPL]]
deps = ["InteractiveUtils", "JuliaSyntaxHighlighting", "Markdown", "Sockets", "StyledStrings", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "62389eeff14780bfe55195b7204c0d8738436d64"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.1"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "5b3d50eb374cea306873b371d3f8d3915a018f0b"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.9.0"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6d40b2fe70437b01397d2a4d5b020008da4e7019"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.5.2+0"

[[deps.Roots]]
deps = ["Accessors", "CommonSolve", "Printf"]
git-tree-sha1 = "e6ffa7bd4f8d0b8744d18f219304738d952f9a37"
uuid = "f2b01f46-fcfa-551c-844a-d8ac1e96c665"
version = "3.0.11"

    [deps.Roots.extensions]
    RootsChainRulesCoreExt = "ChainRulesCore"
    RootsForwardDiffExt = "ForwardDiff"
    RootsIntervalRootFindingExt = "IntervalRootFinding"
    RootsSymPyExt = "SymPy"
    RootsSymPyPythonCallExt = "SymPyPythonCall"
    RootsUnitfulExt = "Unitful"

    [deps.Roots.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
    IntervalRootFinding = "d2bf35a9-74e0-55ec-b149-d360ff49b807"
    SymPy = "24249f21-da20-56a4-8eb1-6a02cf4ae2e6"
    SymPyPythonCall = "bc8888f7-b21e-4b7c-a06a-5d9c9496438c"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.ScopedValues]]
deps = ["HashArrayMappedTries", "Logging"]
git-tree-sha1 = "67a144433c4ce877ee6d1ada69a124d6b1ecf7be"
uuid = "7e506255-f358-4e82-b7e4-beb19740aa63"
version = "1.6.2"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "9b81b8393e50b7d4e6d0a9f14e192294d3b7c109"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.3.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "084c47c7c5ce5cfecefa0a98dff69eb3646b5a80"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.10"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.ShiftedArrays]]
git-tree-sha1 = "503688b59397b3307443af35cd953a13e8005c16"
uuid = "1277b4bf-5013-50f5-be3d-901d8477a67a"
version = "2.0.0"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"
version = "1.11.0"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "13cd91cc9be159e3f4d95b857fa2aa383b53772a"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.3"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.12.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "429071b23f4c9a13fb6582f807cc2ef454082408"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.9.0"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "e2b53ce13a53367e96601081e33d34746b571bad"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.5"
weakdeps = ["SparseArrays"]

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "178ed29fd5b2a2cfc3bd31c13375ae925623ff36"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.8.0"

[[deps.StatsBase]]
deps = ["AliasTables", "DataAPI", "DataStructures", "IrrationalConstants", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "adb9da019510162e67a4493fc235c23203d8b09e"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.34.13"

[[deps.StatsFuns]]
deps = ["HypergeometricFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "91a5737baed20ee31f3faea0e51f57461f6a689e"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "2.2.1"

    [deps.StatsFuns.extensions]
    StatsFunsChainRulesCoreExt = "ChainRulesCore"
    StatsFunsInverseFunctionsExt = "InverseFunctions"

    [deps.StatsFuns.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.StatsModels]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "Printf", "REPL", "ShiftedArrays", "SparseArrays", "StatsAPI", "StatsBase", "StatsFuns", "Tables"]
git-tree-sha1 = "0db41c4e0d9f3fa195395a6401a8290752c9cd3d"
uuid = "3eaba693-59b7-5ba5-a881-562e759f1c8d"
version = "0.7.10"

[[deps.StringManipulation]]
deps = ["PrecompileTools", "StyledStrings"]
git-tree-sha1 = "9e3a02d73a8f0a9be04e677dbef758aab40f8bea"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.6.1"

[[deps.StructUtils]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "ad435e30854ed0f50f4b7f67edd71664afecc5d8"
uuid = "ec057cc2-7a8d-4b58-b3b3-92acb9f63b42"
version = "2.10.0"

    [deps.StructUtils.extensions]
    StructUtilsDataFramesExt = ["DataFrames"]
    StructUtilsLazilyInitializedFieldsExt = ["LazilyInitializedFields"]
    StructUtilsMeasurementsExt = ["Measurements"]
    StructUtilsStaticArraysCoreExt = ["StaticArraysCore"]
    StructUtilsTablesExt = ["Tables"]

    [deps.StructUtils.weakdeps]
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    LazilyInitializedFields = "0e77f7df-68c5-4e49-93ce-4cd80f5598bf"
    Measurements = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
    StaticArraysCore = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
    Tables = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.8.3+2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "a94d9bdda1b7bed0046cea645639ab3f62196fac"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.14.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.TranscodingStreams]]
git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.11.3"

[[deps.Tricks]]
git-tree-sha1 = "311349fd1c93a31f783f977a71e8b062a57d4101"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.13"

[[deps.URIs]]
deps = ["Serialization"]
git-tree-sha1 = "0392e5e3c5327b90a487b0ff3e818c4aecd3660b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.7.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.ZipFile]]
deps = ["Libdl", "Printf", "Zlib_jll"]
git-tree-sha1 = "f492b7fe1698e623024e873244f10d89c95c340a"
uuid = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
version = "0.10.1"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.64.0+1"

[[deps.p7zip_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.7.0+0"
"""

# ╔═╡ Cell order:
# ╟─ebffea60-3284-50a6-a187-2530b8a0d84a
# ╠═a63d3d12-1165-5a5a-a889-4c1bc9d4a6ab
# ╠═c44336d3-0c16-5409-98fb-d90af0d9fdb8
# ╟─efccf287-e8e7-549a-bba7-38b0b6fe6726
# ╠═562689cd-12a1-5c6b-b8ac-b25f7b688993
# ╠═0305acd4-985a-55d8-957a-03d0921fb789
# ╠═b6912c79-71ea-51c4-9bd6-5ba928ec51a0
# ╟─ad3a6f5f-cd8e-5870-8e82-dc780c1c1a27
# ╠═feffbc4d-54a4-5d16-86ff-811d2b2d81d6
# ╠═1303d76d-6fdf-5f8e-a2db-c8cd23f24cbd
# ╟─9bce7da4-2b09-59b6-8715-b5b4d4166a25
# ╠═171d4851-26cc-5768-8d37-956cd08e51b2
# ╠═1bba47d4-70c3-582a-8f77-5aac8e7f06c4
# ╠═bb3b1f2e-1b5d-521f-a296-1192e6170367
# ╟─d7564924-ebaf-558e-b13f-6aeb6e2aeade
# ╠═304c09d6-5c8d-5af1-ab37-b4ef2d3e4654
# ╟─bdb16eac-75e6-5fa0-bc10-0b6b3d44b018
# ╠═435dfd91-3d65-5ae9-85d2-bdd138fc8d19
# ╟─63e76eb2-021a-53a7-a3c7-ee30469b45d6
# ╠═6f24e747-2626-5575-bc0b-43c7ce63963e
# ╠═f2ca76cb-50ef-57b5-a2f3-2d83a1591dab
# ╠═53dff4ce-a835-50ee-aa1c-123ed4fa6bb5
# ╟─5163a58d-1f1d-5f85-9c64-91439be24927
# ╟─4d31ac5f-87e4-5533-93e2-a0aa0d1f9979
# ╠═cc226063-d7c0-5f44-a4f9-77909ffad1a4
# ╠═9449bbe3-afb1-5fc0-980c-bcfc598c158b
# ╠═6d9d63da-cd2a-5310-9c77-ea632bb44839
# ╠═8b2b4aaf-2b4e-58fd-8cf0-ff0ef19b8005
# ╟─1c230219-435f-5ee3-a2af-4f3f592da8d6
# ╟─4705ac92-e1b9-521c-9ed9-6a53395c62f1
# ╠═61ab0fcd-5ebb-56e8-8add-ee4774067bc6
# ╟─ca6eba9e-a96e-5c2e-a738-122b427347a9
# ╠═e86a54ec-d2ce-5e2d-ae80-1d7274097986
# ╠═d4f3404d-71eb-5e62-89f7-ad1b8ebb6919
# ╠═c136ce26-4cd2-501a-b0e3-eb5b07da829f
# ╠═22a123ef-912a-5eea-921b-722060276e33
# ╟─de74dd97-6b0c-5e00-b81e-9c68d07d26a8
# ╠═0fc8bbc0-a2f8-5a5e-a677-0e23b60ff107
# ╟─fb2f234a-b2d3-551c-a97a-d3dea1f6d41e
# ╠═6d1f6071-f74b-5c53-afcb-6c0960eb6e01
# ╠═b911e4d1-7739-5541-94b8-9c301df5ff5a
# ╠═c680c62f-b073-5bb9-b152-e084fa180d01
# ╠═3f0f5d24-c311-55ea-8c66-77a1594ef1cf
# ╠═0dc17052-2e7f-5d2f-bcf6-61970557a088
# ╠═7578107e-672a-57ef-94df-a931f46ae9ca
# ╟─35d5f8d9-8e08-5c20-a3a2-c4b41a315ca1
# ╟─32bbc87c-3e7c-568c-acd9-e33258492725
# ╠═17805076-f655-54ad-8acb-b4a2c2434eb6
# ╠═390b045a-8150-59c7-baf4-fb500b860fdd
# ╠═3b7b75c9-7789-5b44-96d8-b8b604b38206
# ╠═178c89a9-f37b-56e3-8d9d-de4a8e579338
# ╠═b329aad0-642b-5ddf-bdbd-5518de93cce0
# ╟─87c1d7e0-3d8b-5233-aebd-a8cf86d7054d
# ╠═372cb156-fe68-5b22-9bbe-265d08a201a7
# ╠═3e6ae508-0c3b-547c-9a55-1ed68fd25e60
# ╠═fe727064-54f8-5036-97d2-75616b81927d
# ╟─da508975-08d0-55ac-90aa-81f99ef07e99
# ╠═55251e43-b715-5145-aa8a-b23098e32718
# ╟─93a20dce-e811-5e4e-97d4-354996878eb4
# ╠═77017bd9-3dd7-5844-be4c-11b4bf4976ac
# ╟─65c7c8d7-69a7-50c8-a326-6bfe14aea87e
# ╠═079e994d-5d6d-58c9-8c86-f7ff0061857d
# ╟─644ef682-72a7-5f5d-8d69-0f5736c00458
# ╠═fea21b6a-48f9-54ed-86d6-7c94d4ca2423
# ╟─265196b7-2ab3-53a9-adca-d6742640bcad
# ╠═bb498d73-0573-5b7f-b301-70b8689c29be
# ╠═c966558b-a497-5d8e-a5f4-446e97ca4fcc
# ╟─cc46ea37-fa1a-5f23-ae18-eae34ae3faf0
# ╠═b28a7a1e-7604-5cd8-beec-f45d1fed301e
# ╟─53d425c4-ec93-5190-9cdf-0a6d3b649bba
# ╠═a4ae5ec9-672e-57c8-b733-b1ced8c4040e
# ╠═858b2fe4-8892-5aa3-a845-6cf3b98858fe
# ╟─c42c9e27-18a0-5873-bd42-c7709a75bf6e
# ╠═fe299749-6fbf-5b0c-84ad-7241facf0912
# ╠═1cba0456-559b-51f2-b168-b54671242470
# ╠═9385f2bb-02d5-5601-b607-21ab83cbc7af
# ╠═03c595c5-a8c8-59c7-a678-23ec0f6c7ca8
# ╟─0f05e29d-fa30-5e21-be0a-893cc893bf6c
# ╠═934bff83-0986-5c08-9ab8-a1b8a906869e
# ╠═3584448f-db33-501d-9d2e-aded839ec383
# ╟─123aff1a-ce1a-5c4e-abe7-4acc1e8abe67
# ╠═c08549a5-8d31-5bf5-9998-eac01a9a8fec
# ╠═d7e240c4-43e9-5623-9c2f-c05e1632613b
# ╠═d859bbe4-8de5-56d5-889e-4966555a7609
# ╠═1bf27a1a-1c7b-52b5-9fe6-d6c47d3ae62b
# ╟─6c29df36-6f08-5490-a746-a8919f58520d
# ╠═f99f9b53-725c-51fb-9a60-e34f242ddd5c
# ╠═8f0f82d1-0133-5e92-bc63-15f82f2c3e6b
# ╟─13e28fbf-f753-55f4-8bcf-95ab485955a4
# ╠═2a26b984-1664-5c18-9897-d084443069a5
# ╟─d8ff42f8-1f3e-5c15-85f4-0b5f735b6d3c
# ╠═96ed9737-95b4-5f80-8f24-7ca235f6338f
# ╠═591d23d4-f035-57e9-9a66-1c4b216e0234
# ╠═8c5f01cd-b1e0-5499-babb-29cefa12bea8
# ╠═f0428f99-1cc0-50b4-8712-fcecf7a0cde0
# ╟─cfd3c36b-5c47-522f-a3c8-3c6fc989ecd6
# ╠═02b8eb52-3091-56c9-baed-0163c38821f4
# ╠═22039358-cdb9-591a-9886-9b4f9246dd14
# ╟─e1171cbd-b81e-5422-aabf-c15c41a9c285
# ╠═2e58cdde-e6b3-5344-a92c-4e71d3787e78
# ╠═ea7eb588-da33-58c9-8514-431796a2cc0f
# ╠═e7e18744-b85d-570e-9f26-3deeb819d163
# ╠═fb959d59-774a-5f92-b4ea-8857c0244794
# ╠═e9f21b17-e6f1-5046-92c2-5c558b143ae4
# ╟─105a4a50-0a63-5c4c-8871-80b10ffb25bf
# ╟─1a807fce-4535-511c-a246-06e0f8c5740a
# ╟─9cf637e5-ca1b-57f7-b78c-b581b4aeaf86
# ╠═22aefb06-4242-5a19-ae35-144580fe963c
# ╠═a0df578d-b530-5c6c-8a80-7b62a2eb8456
# ╠═c1047b10-9bed-5545-99fe-7a42e22f6c78
# ╠═b87d49db-2bb0-5cf1-b17f-b042daa26ea3
# ╟─15abc70e-9d9b-5acf-b8f7-f19fbfbb309e
# ╠═858996ad-09da-542f-9e41-d0a85dbf141b
# ╠═d42ac367-1f08-5df6-9406-45024724852b
# ╠═38160394-806f-5fea-87ce-3ce423b72906
# ╠═5195d130-051e-5595-9b61-aab379b3ec3d
# ╠═3667542c-4d87-5918-911b-06e44bd847bf
# ╠═818dfb44-fce8-5db8-b1b5-a6f83edb6adc
# ╠═91e1aa7a-14c1-5374-8241-6b04338244af
# ╠═857c3f8d-abc6-57d3-8078-0dd96feb194b
# ╠═683c0cec-1766-52d0-8c92-f66902c5fc10
# ╠═0143083b-8b8d-524d-9ca4-250b5c3fb636
# ╠═7b5d9cc3-59b1-533a-b201-3147f3b38662
# ╠═d16c3251-6dec-54f3-84e3-5cc5b1947163
# ╠═1e05a5cb-5244-507a-88ac-35c5ac0d3c79
# ╠═3fcb3680-3d74-5915-a5ee-07affeacf74b
# ╠═82701de8-7b3d-55a7-b463-125483ad7e5c
# ╠═e3860fe1-35a6-52b7-a265-61a04c1caecd
# ╠═206a98b3-cc43-5051-81b6-c0f6243e4ebe
# ╠═fd92b114-882b-5d58-b796-65f16b7ed036
# ╠═1c616f39-34a0-5edb-afa8-ad0b5422e1f4
# ╠═534d78c1-20ba-5c47-99c9-4eb9ccba4ec9
# ╠═6bd45608-925d-58c1-a0e5-cafe0955d309
# ╠═4a891c07-30cd-51ed-97dc-ac9eaa5f7a19
# ╠═7599cc52-706c-5fde-bbda-114308464a76
# ╠═98b9ee02-e261-54e5-86fc-88180cef1f06
# ╠═6cd0859e-fac1-59a6-a6ed-511e9f9a8ce7
# ╠═db2eb977-c594-57ef-8048-82771ef025bd
# ╠═36774504-de25-5f18-8bb1-d7880a3f1c35
# ╟─dee730ee-2889-5b4f-ae31-5622273e4bba
# ╠═92e8060a-a6d5-5486-b032-d7179a07cf72
# ╠═baa12b25-e765-5a2c-be56-a29f876f8a6a
# ╠═ebe45b85-07cc-5d31-bba3-7cb4d0dacd4a
# ╠═a00d7e2c-01d4-5eee-9fd8-66c1e6389d98
# ╠═959f7173-6ca3-5048-9175-607b888bfc62
# ╠═2c41acbd-93e5-5a01-b66f-4454b8070d88
# ╠═4cd4d389-28de-56f3-8569-17ab4ecd52ec
# ╠═5db10ec2-3cfe-5518-a382-8393eea3cd1d
# ╠═bce6e04e-f865-5ce7-b3d6-44056a981dd6
# ╠═205d27f9-0d20-5af5-a5b2-20ba0c4bf88c
# ╠═a0317095-3a0f-57e1-b064-7d73b4f8be12
# ╠═c823afbe-b119-595e-9c9a-30718077ec4c
# ╠═73a02ae8-8320-5173-b948-d57a43ad94ab
# ╠═6e36fe37-218a-5fcb-8ff2-c520f54fa1bc
# ╠═0a520e4b-f714-5812-967b-b7f9c34f89ee
# ╠═ffff8049-1a0d-55ca-9372-57a273418367
# ╠═871f95e4-b3ba-50a1-94e2-64518444a161
# ╠═4790e3ca-3e22-5eb3-a0eb-f2ebc5232637
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
