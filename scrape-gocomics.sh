#! /usr/bin/env bash

# GoComics scraper 1.0

# Confirm installation of prerequisites
declare -a PREREQUISITES=( date curl jq xargs hxselect hxpipe head cut rev )
for PREREQUISITE in ${PREREQUISITES[@]}
do
    which "$PREREQUISITE" > /dev/null 2> /dev/null
    WHICH_EXIT_CODE=$?
    if [[ $WHICH_EXIT_CODE != 0 ]]; then
        echo "$PREREQUISITE is not installed. (Have you installed html-xml-utils?) Aborting."
        exit 1
    fi
done

# Parse arguments
if [[ -z $1 ]] || [[ -z $2 ]] || [[ -z $3 ]]; then
    echo "Usage: $0 comic-name start-date end-date"
    exit 0
fi

COMIC_NAME=$1

START_DATE=$(date -d $2 -I 2> /dev/null)
DATE_EXIT_CODE=$?
if [[ $DATE_EXIT_CODE != 0 ]]; then
    echo "Invalid start date: $2"
    exit 1
fi

END_DATE=$(date -d $3 -I 2> /dev/null)
DATE_EXIT_CODE=$?
if [[ $DATE_EXIT_CODE != 0 ]]; then
    echo "Invalid end date: $3"
    exit 1
fi

# Ensure start date is not after end date
START_TIMESTAMP=$(date -d $START_DATE +%s)
END_TIMESTAMP=$(date -d $END_DATE +%s)
if [[ $END_TIMESTAMP -lt $START_TIMESTAMP ]]; then
    SWAP=$START_DATE
    START_DATE=$END_DATE
    END_DATE=$SWAP
fi

# Print informative message
echo "Finding available $COMIC_NAME strips from $START_DATE to $END_DATE (inclusive)"

# Find available dates
DATES=$(curl -fs "https://www.gocomics.com/api/service/v2/assets/feature-runs/$COMIC_NAME?dateAfter=$START_DATE&dateBefore=$END_DATE" -H 'User-Agent: Mozilla/5.0' | jq -r '.dates[]' | xargs -I % date -d % -I)

CURL_EXIT_CODE=$?
if [[ $CURL_EXIT_CODE != 0 ]]; then
    echo "Error identifying available dates"
    exit 1
fi

# Execute download
for CURRENT_DATE in $DATES; do
    echo "Downloading $COMIC_NAME for $CURRENT_DATE...";
    YEAR=$(date +%Y -d "$CURRENT_DATE")
    MONTH=$(date +%m -d "$CURRENT_DATE")
    DAY=$(date +%d -d "$CURRENT_DATE")

    PAGE_URL="https://www.gocomics.com/$COMIC_NAME/$YEAR/$MONTH/$DAY"
    echo "Scraping $PAGE_URL"
    IMAGE_URL=$(curl -fs "$PAGE_URL" -H 'User-Agent: Mozilla/5.0' | hxselect "meta[property='og:image']" | hxpipe | head -n 1 | cut -d " " -f 3)

    CURL_EXIT_CODE=$?
    if [[ $CURL_EXIT_CODE != 0 ]]; then
        echo "Error downloading page: $PAGE_URL"
        exit 1
    fi

    if [[ -z "$IMAGE_URL" ]]; then
        echo "Failed to scrape image from $PAGE_URL"
        exit 1
    fi

    echo "Determining image type"
    IMAGE_TYPE=$(curl -Is -o /dev/null -w %{content_type} "$IMAGE_URL")

    EXTENSION=$(echo "$IMAGE_TYPE" | cut -d "/" -f 2)
    FILE_PATH="$COMIC_NAME/$YEAR-$MONTH-$DAY.$EXTENSION"

    echo "Downloading $IMAGE_URL"
    curl -fs "$IMAGE_URL" --create-dirs -o "$FILE_PATH"

    CURL_EXIT_CODE=$?
    if [[ $CURL_EXIT_CODE != 0 ]]; then
        echo "Error downloading image: $IMAGE_URL"
        exit 1
    fi
    
    echo "Saved as $FILE_PATH"
    CURRENT_DATE=$(date -I -d "$CURRENT_DATE + 1 day")
done
