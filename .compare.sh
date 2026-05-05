#!/bin/bash
OURS="/Users/claresegrue/Documents/Perficient Projects/univision"
THEIRS="/Users/claresegrue/Documents/Perficient Projects/univision/.compare-repo"
printf "%-25s %8s %8s\n" "metadata" "OURS" "THEIRS"
printf "%-25s %8s %8s\n" "-------" "----" "------"
for dir in objects classes triggers lwc flows permissionsets quickActions applications flexipages reports dashboards reportTypes globalValueSets customPermissions customMetadata sharingRules tabs layouts namedCredentials labels staticresources contentassets documents workflows; do
  o=$(find "$OURS/force-app/main/default/$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  t=$(find "$THEIRS/force-app/main/default/$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
  printf "%-25s %8s %8s\n" "$dir" "$o" "$t"
done
echo "---"
printf "%-25s %8s %8s\n" "fields" "$(find "$OURS/force-app/main/default/objects" -name '*.field-meta.xml' 2>/dev/null | wc -l | tr -d ' ')" "$(find "$THEIRS/force-app/main/default/objects" -name '*.field-meta.xml' 2>/dev/null | wc -l | tr -d ' ')"
printf "%-25s %8s %8s\n" "validation-rules" "$(find "$OURS/force-app/main/default/objects" -name '*.validationRule-meta.xml' 2>/dev/null | wc -l | tr -d ' ')" "$(find "$THEIRS/force-app/main/default/objects" -name '*.validationRule-meta.xml' 2>/dev/null | wc -l | tr -d ' ')"
printf "%-25s %8s %8s\n" "record-types" "$(find "$OURS/force-app/main/default/objects" -name '*.recordType-meta.xml' 2>/dev/null | wc -l | tr -d ' ')" "$(find "$THEIRS/force-app/main/default/objects" -name '*.recordType-meta.xml' 2>/dev/null | wc -l | tr -d ' ')"
printf "%-25s %8s %8s\n" "test-classes" "$(find "$OURS/force-app/main/default/classes" -name '*Test.cls' 2>/dev/null | wc -l | tr -d ' ')" "$(find "$THEIRS/force-app/main/default/classes" -name '*Test.cls' 2>/dev/null | wc -l | tr -d ' ')"
