# ВАЖНО: версия для загрузки через браузер

В этой версии 48 comparator cases упакованы в один `FROZEN_ADAPTER_48_CASES.zip`.
Это сделано только для транспорта: SHA-256 архива зафиксирован и проверяется до распаковки.
Количество файлов репозитория уменьшено ниже лимита browser upload GitHub.

# UNI-10 External Certification GitHub Runner

Назначение: выполнить **Gates 1–5** внешней сертификации в двух свежих GitHub-hosted Linux jobs:
`execution` и `recheck`.

## Важно

Этот runner **НЕ закрывает Gate 6** и не создаёт `EXTERNAL_CERTIFICATION_FINAL_PACKAGE`.
Gate 6 — external signer / trust-anchor authentication — остаётся `OPEN`.

Runner не изменяет canonical completion archive:

`UNI10_FSC_SVA_RND_COMPLETION_20260808.zip`

Ожидаемый SHA-256:

`927b228156c3c5fdc817019dacf9155fc33b07a1db0059ffbc81a92951eadf2b`

## Как запустить

1. Создайте новый **private** GitHub repository.
2. Распакуйте этот ZIP на компьютере.
3. Загрузите **содержимое папки** `UNI10_EXTERNAL_CERTIFICATION_GITHUB_RUNNER` в корень repository.
   В корне GitHub должны быть `.github`, `adapter`, `completion`, `scripts`, `pins`, `lean-toolchain`.
4. Откройте вкладку **Actions**.
5. Выберите workflow **UNI-10 External Certification Gates 1-5**.
6. Нажмите **Run workflow** → **Run workflow**.
7. После завершения откройте run.
8. В разделе **Artifacts** скачайте:
   `UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_EVIDENCE`.
9. Распакуйте скачанный GitHub artifact. В нём будут:
   - `UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_EVIDENCE.zip`
   - `UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_EVIDENCE.zip.sha256`
   - `TECHNICAL_CERTIFICATION_SUMMARY.json`
10. Пришлите эти три файла обратно в ChatGPT.

## Что выполняется

- G01: Lean 4.32.2 compile/kernel — `lean FSC_Core.lean`.
- G02: comparator по 48 отдельно frozen Challenge/Solution cases — один target theorem на case.
- G03: pinned nanoda через comparator (`enable_nanoda=true`) во всех 48 cases.
- G04: TLA+ Tools 1.7.4, `workers=1`, обе модели.
- G05: pinned external `lrat-check`: 15/15 valid proofs PASS и 15/15 deterministic mutants REJECT.
- Каждый gate выполняется снова во втором свежем GitHub runner job.

## Fail-closed

Любой FAIL/BLOCKED/MISSING не превращается в PASS.
Workflow может стать красным — это нормально: artifact evidence всё равно должен быть сохранён.
