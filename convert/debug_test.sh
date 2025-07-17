#!/bin/bash

# Simple test to find where the script exits
echo "Testing choice handling..."

choice="3"
echo "Choice is: $choice"

case $choice in
    1)
        echo "Option 1 selected"
        exit 1
        ;;
    2|y|yes|Y|YES)
        echo "Option 2 selected"
        ;;
    3|n|no|N|NO)
        echo "Option 3 selected"
        echo "This should continue..."
        ;;
    4|rm|remove|delete)
        echo "Option 4 selected"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo "After case statement"
echo "Script should continue here"
echo "Testing complete"
