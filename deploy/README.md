# Drift hos Att Stays

Denne kopien av `googleads/google-ads-mcp` kjører i Google Cloud for Att Stays og er koblet til claude.ai som connectoren «Google Ads». Serveren kan bare lese fra Google Ads.

## Oppsett

| Del | Verdi |
|---|---|
| Google Cloud-prosjekt | `att-google-ads` (ID `nimble-lead-513509-g5`) |
| Cloud Run-tjeneste | `google-ads-mcp`, `europe-north1`, maks én instans |
| Adresse i claude.ai | `https://google-ads-mcp-zsawebeycq-lz.a.run.app/mcp` |
| Innlogginger | Firestore `(default)`, `eur3`, kryptert |
| Hemmeligheter | Secret Manager: `ads-mcp-oauth-client-secret`, `ads-mcp-jwt-signing-key`, `ads-mcp-storage-encryption-key` |
| OAuth-klient | «Claude connector», Internal (kun attstays.com) |
| Redirect-URI-er på klienten | `https://claude.ai/api/mcp/auth_callback` og `<adresse>/auth/callback` |
| Google Ads API-tilgang | Explorer (2 880 operasjoner per døgn mot produksjonskontoer) |

## Endring i forhold til Google

Eneste endring: `Dockerfile` installerer `.[firestore]`, så innlogginger overlever omstart av Cloud Run.

## Oppdatere

1. Hent endringer fra `googleads/google-ads-mcp` på en egen gren og lag en endringsforespørsel. Les endringene før fletting.
2. Etter fletting til `main`: åpne Cloud Shell i prosjektet og kjør

   ```bash
   rm -rf ~/gam && git clone --depth 1 https://github.com/ATTSTAYS/google-ads-mcp.git ~/gam && bash ~/gam/deploy/deploy.sh
   ```

3. Siste linje skal vise HTTP 401. Test deretter i Claude: «Hvilke Google Ads-kontoer har jeg tilgang til?».

Bytte client secret: lag ny secret på OAuth-klienten, kjør med `NEW_SECRET=1`, deaktiver den gamle i Secret Manager og på klienten.

## Kjente feil

| Feil | Årsak | Løsning |
|---|---|---|
| `redirect_uri_mismatch` | Serverens callback mangler på OAuth-klienten | Legg til `<adresse>/auth/callback` |
| `invalid_client: The provided client secret is invalid` | Feil eller dobbelt innlimt secret | Skriptet sjekker nå at lengden er 35 |
