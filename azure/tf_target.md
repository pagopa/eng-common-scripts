# Python script to generate targets from a single terraform file

This script reads the given terraform file and generates the "-target" expression containing all the resources and modules defined in the given file 
The output can be then used to execute `terraform.sh <action> <env> <script_output>` 

## Usage

```shell
python tf_target.py <tf file path>
```


Feel free to modify and enhance the README.md to suit your requirements.