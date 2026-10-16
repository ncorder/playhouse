# Bike Sharing Project: Midterm M2, Baseline Linear Regression

Daily Capital Bikeshare rentals in Washington, D.C., 2011–2012 (UCI *Bike Sharing* dataset).

| File | Contents |
|---|---|
| `M2 Baseline Linear Regression.pdf` | The M2 report: a one-page executive summary, 4 pages of main text (figures included) and an appendix with extra diagnostics. |
| `M2 Baseline Linear Regression.docx` | The same report as an editable Word file. |
| `m2BaselineRegression.jl` | Pluto notebook with the full M2 analysis (Julia, PlutoPlotly). |
| `m2BaselineRegression.html` | Static HTML export of the notebook. Open it in a browser; the plots are interactive (hover to see dates). |
| `figures/` | The report's figures, exported from the notebook (Appendix A). |
| `data/day.csv`, `data/Readme.txt` | UCI daily data file (used for all models) and its readme. |
| `data/hour.csv` | UCI hourly data file, used only to count the rainy hours on the days with the largest residuals (Section 8.3). |

## Running the notebook

```julia
using Pluto
Pluto.run(notebook = "Bike Sharing Project/m2BaselineRegression.jl")
```

Pluto installs the exact package versions recorded in the notebook. The data are read from `data/`; if a file is missing, the notebook downloads it from UCI. To regenerate the report's figures, tick the checkbox in Appendix A of the notebook.

## Structure

The notebook follows the Exam 1 review template and uses only methods covered there:

1. Simple regression: model statement, error distribution, 99 % CI and interpretation of the slope.
2. Baseline multiple regression: summary block.
3. Residual-vs-predictor plots and nested `anova`-style F-tests for curvature in temperature.
4. A "kitchen-sink" model with feels-like temperature and month: diagnosing multicollinearity from the summary block and VIFs.
5. Backward selection by AIC and by BIC.
6. Inference with the final model: CIs, t-tests for day type, term-wise F-tests, and a prediction with its CI and PI (Thanksgiving 2012).
7. Assumption checks with R's four `plot(lm)` plots: residuals vs fitted, normal Q–Q, scale–location and residuals vs leverage (Cook's distance), plus a time-order residual plot and a table of the days with the largest residuals.
8. Partial-effect plots and interpretation of five key coefficients.

## Data

Fanaee-T, H. (2013). *Bike Sharing* [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5W894>. Licensed CC BY 4.0.
