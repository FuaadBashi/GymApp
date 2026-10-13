import marimo

__generated_with = "0.25.1"

app = marimo.App(width="medium")

@app.cell
def _():
    import marimo as mo
    from gymstudio.notebook import load_context
    from gymstudio import analysis, stats, progression
    mo.md("# Training explorer\nEdit the cells below to explore the same snapshot and tested functions as Studio.")
    return mo, load_context, analysis, stats, progression

@app.cell
def _(mo):
    refresh = mo.ui.button(label="Reload dashboard snapshot")
    refresh
    return (refresh,)

@app.cell
def _(refresh, load_context):
    refresh.value
    context = load_context()
    history = context.history
    settings = context.settings
    tables = context.tables
    return context, history, settings, tables

@app.cell
def _(mo, history):
    exercise = mo.ui.dropdown(options={ex.name + " · " + eid: eid for eid, ex in history.exercises.items() if history.sessions_for(eid)}, label="Exercise")
    exercise
    return (exercise,)

@app.cell
def _(exercise, history, settings, analysis, mo):
    detail = analysis.exercise_detail(history, exercise.value, settings) if exercise.value else None
    mo.ui.table(detail["points"] if detail else [], selection=None)
    return (detail,)

@app.cell
def _(mo, context, history):
    # Your own metric. Change this code, then press Publish.
    custom_value = len(history.workouts)
    publish = mo.ui.run_button(label="Publish finished-workout count to Overview")
    publish
    return custom_value, publish

@app.cell
def _(context, custom_value, publish, mo):
    result = context.publish("Finished workouts", custom_value, "sessions", "Notebook metric on this snapshot") if publish.value else None
    mo.md("Published locally." if result else "Your custom metrics appear on Overview after you publish them.")
    return (result,)

if __name__ == "__main__":
    app.run()
