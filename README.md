# Generate-delta-package
This repository contains code for generating package for delta changes for Salesforce project using ANT based project structure.

## Before trying this program, please do the following steps: 
- If you need to run test classes during validation please update the [TestClassMapping.json](TestClassMapping.json) containing apex class mapping to its test class.
- Please update your Salesforce credentials in [build.properties](build.properties)

### To generate package for changed files, run the following command:

```
./gdp.sh -s feature/someStory -t release/Version -d /path/to/repository
```
### To run validation without test class, execute the following:
```
cp build_template.xml build.xml && ant validate
```
### To run validation with test class, execute the following:
```
ant validateWithTestClass
```
