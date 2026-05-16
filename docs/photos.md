# Photos

Photos support includes metadata on Place Details and a helper to fetch a photo URL.

## Details (metadata)

```bash
goplaces details "PLACE_ID" --photos
```

## Photo URL

```bash
goplaces photo "places/PLACE_ID/photos/PHOTO_ID" --max-width 1200
```

## Library

```go
details, err := client.DetailsWithOptions(ctx, goplaces.DetailsRequest{
    PlaceID:       "PLACE_ID",
    IncludePhotos: true,
})

photo, err := client.PhotoMedia(ctx, goplaces.PhotoMediaRequest{
    Name:       details.Photos[0].Name,
    MaxWidthPx: 1200,
})
```

## Notes

- Photo media always returns a URL (skip redirect) for easy downloading.
- Provide `max-width` or `max-height`; each provided dimension must be 1-4800.
