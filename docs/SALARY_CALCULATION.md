# Salary Calculation

Salary math is implemented in `SalaryCalculator` and `SalaryEstimate`.

Rules:

- Base salary is stored as integer minor units.
- Day rate is manual or derived from base salary divided by paid days.
- Hour rate is manual or derived from day rate divided by standard minutes per day.
- Regular work is covered by base salary.
- Overtime adds hour-rate based pay.
- Extra days add day-rate based pay.
- Official holiday worked entries support additional-pay or total-including-base semantics.
- Finalized salary periods store immutable snapshots.
- Salary payment recording is atomic through `record_salary_payment` and prevents duplicate salary-income transactions.
