# TÄRKEÄÄ: selainlataukseen sopiva versio

Tässä versiossa 48 comparator-casea on pakattu yhteen `FROZEN_ADAPTER_48_CASES.zip`-arkistoon.
Arkiston SHA-256 tarkistetaan ennen purkamista. Tämä vähentää repositoryyn ladattavien
tiedostojen määrän GitHubin selainlatauksen rajan alapuolelle.

# UNI-10 External Certification GitHub Runner

Tämä paketti suorittaa ulkoisen sertifioinnin tekniset portit **G01–G05** kahdessa erillisessä
tuoreessa GitHub-hosted Linux -ajossa: `execution` ja `recheck`.

**Gate 6 (ulkoinen allekirjoittajan/trust-anchor -todennus) jää tarkoituksella OPEN-tilaan.**
Tämä runner ei luo `EXTERNAL_CERTIFICATION_FINAL_PACKAGE`-pakettia eikä tee promotionia.

Canonical completion SHA-256:

`927b228156c3c5fdc817019dacf9155fc33b07a1db0059ffbc81a92951eadf2b`

## Käynnistys

1. Luo uusi private GitHub repository.
2. Pura tämä ZIP omalle tietokoneelle.
3. Lataa kansion `UNI10_EXTERNAL_CERTIFICATION_GITHUB_RUNNER` sisältö repositoryn juureen.
4. Avaa GitHubissa **Actions**.
5. Valitse **UNI-10 External Certification Gates 1-5**.
6. Paina **Run workflow**.
7. Kun ajo päättyy, lataa artifact:
   `UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_EVIDENCE`.
8. Toimita takaisin kolme tiedostoa:
   `UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_EVIDENCE.zip`,
   `.zip.sha256` ja `TECHNICAL_CERTIFICATION_SUMMARY.json`.

Kaikki tarkistukset ovat fail-closed: epäonnistumista ei muuteta PASS-tulokseksi.

Comparator-adapteri sisältää 48 erillistä frozen casea: jokaisessa vain yhden kohdeteoreeman proof-body korvataan Challenge-versiossa, muut deklaraatiot säilyvät byte-identical Solution/source-versioon nähden.
