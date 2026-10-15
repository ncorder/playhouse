# ModernBERT classifier for Equality Arizona's 2022 Sine Die Report categories (excluding Other)
# Run `julia --project modernBERTClassifier.jl`; outside of a SLURM job it submits itself with sbatch.

using Pkg

account = get(ENV, "ACCOUNT", "")
partition = get(ENV, "PARTITION", "standard")
gpus = parse(Int, get(ENV, "GPUS", "1"))
mem = get(ENV, "MEM", "32G")
timeLimit = get(ENV, "TIME", "04:00:00")
epochs = parse(Int, get(ENV, "EPOCHS", "5"))
maxLength = parse(Int, get(ENV, "MAX_LENGTH", "2048"))

modelID = "answerdotai/ModernBERT-base"
outputDir = "modernBERT-equalityArizona"

if !haskey(ENV, "SLURM_JOB_ID")
	Pkg.add(["CondaPkg", "PythonCall", "DataFrames", "Parquet2"])

	using CondaPkg
	CondaPkg.add("python"; version="<3.14", resolve=false)
	CondaPkg.add("transformers"; resolve=false)
	CondaPkg.add("datasets"; resolve=false)
	CondaPkg.add("numpy"; version="<2.4", resolve=false)
	CondaPkg.add("pytorch"; resolve=false)
	CondaPkg.add("accelerate"; resolve=false)
	CondaPkg.add("scikit-learn"; resolve=false)

	jobScript = """
	#!/bin/bash
	#SBATCH --job-name=modernBERT
	$(isempty(account) ? "" : "#SBATCH --account=$account")
	#SBATCH --partition=$partition
	$(gpus > 0 ? "#SBATCH --gres=gpu:$gpus" : "")
	#SBATCH --nodes=1
	#SBATCH --ntasks=1
	#SBATCH --cpus-per-task=4
	#SBATCH --mem=$mem
	#SBATCH --time=$timeLimit
	#SBATCH --output=modernBERT_%j.out

	"$(joinpath(Sys.BINDIR, "julia"))" --project="$(dirname(Base.active_project()))" "$(abspath(@__FILE__))"
	"""
	write("modernBERT.slurm", jobScript)
	run(`sbatch modernBERT.slurm`)
	exit()
end

# Running inside the SLURM job from here on
using CondaPkg
CondaPkg.resolve()

# torch needs these libs from the conda env, which julia can't find on its own (see HFPluto.jl)
for lib in ("libgomp.so.1", "libmkl_core.so.3", "libmkl_gnu_thread.so.3", "libmkl_intel_lp64.so.3")
	path = joinpath(CondaPkg.envdir(), "lib", lib)
	isfile(path) && Base.Libc.Libdl.dlopen(path, Base.Libc.Libdl.RTLD_GLOBAL)
end

using PythonCall, DataFrames, Parquet2, Downloads, Random

datasets = pyimport("datasets")
transformers = pyimport("transformers")
np = pyimport("numpy")
torch = pyimport("torch")
metrics = pyimport("sklearn.metrics")

report = DataFrame(Parquet2.Dataset(Downloads.download("https://codeberg.org/AZLegInfo/datasets/raw/branch/main/equalityArizona2022SineDieReport.parquet")))
categories = setdiff(names(report, Between(:Education, :Other)), ["Other"])

bills = filter(row -> any(!ismissing, row[categories]), report)
bills.label = [findfirst(!ismissing, collect(row[categories])) for row in eachrow(bills)]
# Some bill texts contain invalid UTF-8 (e.g. Latin-1 non-breaking spaces)
bills.text = [map(c -> isvalid(c) ? c : ' ', t) for t in bills.Short_Description .* "\n" .* bills.Introduced_Version_Text]

# Systematic sampling: order by category, then every kth bill from a random start is held out for testing
sort!(bills, :label)
Random.seed!(42)
k = 5
testRows = rand(1:k):k:nrow(bills)
trainRows = setdiff(1:nrow(bills), testRows)

tokenizer = transformers.AutoTokenizer.from_pretrained(modelID)

function toDataset(rows)
	data = datasets.Dataset.from_dict(pydict(Dict("text" => pylist(bills.text[rows]), "label" => pylist(bills.label[rows] .- 1))))
	return data.map(examples -> tokenizer(examples["text"], truncation=true, max_length=maxLength), batched=true)
end

trainData = toDataset(trainRows)
testData = toDataset(testRows)

model = transformers.AutoModelForSequenceClassification.from_pretrained(
	modelID,
	num_labels=length(categories),
	id2label=pydict(Dict(i - 1 => c for (i, c) in enumerate(categories))),
	label2id=pydict(Dict(c => i - 1 for (i, c) in enumerate(categories)))
)

function computeMetrics(evalPred)
	logits, labels = evalPred
	predictions = np.argmax(logits, axis=-1)
	return pydict(Dict(
		"accuracy" => metrics.accuracy_score(labels, predictions),
		"f1" => metrics.f1_score(labels, predictions, average="macro")
	))
end

trainingArgs = transformers.TrainingArguments(
	outputDir,
	learning_rate=5e-5,
	per_device_train_batch_size=8,
	per_device_eval_batch_size=8,
	num_train_epochs=epochs,
	weight_decay=0.01,
	eval_strategy="epoch",
	save_strategy="no",
	fp16=pyconvert(Bool, torch.cuda.is_available()),
	report_to="none"
)

trainer = transformers.Trainer(
	model=model,
	args=trainingArgs,
	train_dataset=trainData,
	eval_dataset=testData,
	processing_class=tokenizer,
	data_collator=transformers.DataCollatorWithPadding(tokenizer=tokenizer),
	compute_metrics=computeMetrics
)

trainer.train()
println(trainer.evaluate())

predictions = np.argmax(trainer.predict(testData).predictions, axis=-1)
println(metrics.classification_report(
	pylist(bills.label[testRows] .- 1),
	predictions,
	labels=pylist(0:length(categories)-1),
	target_names=pylist(categories),
	zero_division=0
))

trainer.save_model(outputDir)
