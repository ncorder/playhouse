# Bike Sharing Project: Midterm M2, Baseline Linear Regression

Daily Capital Bikeshare rentals in Washington, D.C., 2011–2012 (UCI *Bike Sharing* dataset).

| File | Contents |
|---|---|
| `m2BaselineRegression.jl` | Pluto notebook with the full M2 analysis (Julia, PlutoPlotly). |
| `m2BaselineRegression.html` | Static HTML export of the notebook. Open it in a browser; the plots are interactive (hover to see dates). |
| `M2 Baseline Linear Regression.docx` | The M2 paper (4 pages plus an appendix). |
| `figures/` | The paper's figures, exported from the notebook (Appendix A). |
| `data/day.csv`, `data/Readme.txt` | UCI daily data file and its readme. |

## Running the notebook

```julia
using Pluto
Pluto.run(notebook = "Bike Sharing Project/m2BaselineRegression.jl")
```

Pluto installs the exact package versions recorded in the notebook. The data are read from `data/day.csv`; if that file is missing, the notebook downloads it from UCI. To regenerate the paper's figures, tick the checkbox in Appendix A of the notebook.

## Structure

The notebook follows the Exam 1 review template:

1. Simple regression: model statement, error distribution, 99 % CI and interpretation of the slope.
2. Baseline multiple regression: summary block.
3. Component-plus-residual plots and nested `anova`-style F-tests for curvature in temperature.
4. A "kitchen-sink" model with feels-like temperature and month: diagnosing multicollinearity from the summary block and (G)VIFs.
5. Backward selection by AIC and by BIC.
6. Inference with the final model: CIs, t-tests for day type, term-wise F-tests, and a prediction with its CI and PI (Thanksgiving 2012).
7. Assumption checks: linearity, constant variance (Breusch–Pagan), normality (Q–Q, Shapiro–Wilk), leverage and Cook's distance, independence (ACF, Durbin–Watson), and robust (HC3, Newey–West) standard errors.
8. Partial-effect plots and interpretation of the key coefficients.

## Data

Fanaee-T, H. (2013). *Bike Sharing* [Dataset]. UCI Machine Learning Repository. <https://doi.org/10.24432/C5W894>. Licensed CC BY 4.0.
