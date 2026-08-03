# API key setup

`goplaces` uses Google Maps Platform APIs and requires a Google API key.

## Create and configure a key

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and create or select a project.
2. In [APIs & Services → Library](https://console.cloud.google.com/apis/library), enable **Places API (New)**.
3. Enable **Routes API** if you plan to use `route` or `directions`.
4. In [APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials), create an API key.
5. Restrict the key to **Places API (New)** and **Routes API**, plus any application restrictions appropriate for the machine that runs `goplaces`.
6. Export the key before running the CLI:

   ```sh
   export GOOGLE_PLACES_API_KEY="..."
   ```

Add the export to your shell configuration only if that file is private and appropriate for local secrets. The key can also be supplied with `--api-key`, but environment-based configuration avoids putting it in shell history and process arguments.

## Billing and quotas

Google Maps Platform usage is billed and quota-limited. Review the [Places API usage and billing documentation](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing), set quota limits, and configure budget alerts before unattended or high-volume use.

`goplaces` does not proxy requests or manage credentials. Calls go to the configured Google endpoints unless you explicitly set an endpoint override.
