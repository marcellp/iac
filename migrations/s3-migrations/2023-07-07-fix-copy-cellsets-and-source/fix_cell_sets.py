import json
import sys
import os
from collections import Counter

experiment_id = sys.argv[1]

in_file_path = f"./in/{experiment_id}/cellsets.json"
out_file_path = f"./out/{experiment_id}/cellsets.json"

cs = json.load(open(in_file_path))

set_ids = set()
counts = Counter()

for cell_class in cs['cellSets']:
    for cell_set in cell_class['children']:
        # Check, for any cellSet that is child:
        # if cell_set["rootNode"] is set to None (which breaks ScType), 
        #   then set it to False instead.
        # if cell_set["type"] is set to None (which breaks ScType), 
        #   then set it to the type of its parent instead, 
        #   the type in the parent is the same as the one in the child.
        if (cell_set["rootNode"] == None):
            cell_set["rootNode"] = False
        if (cell_set["type"] == None):
            cell_set["type"] = cell_class["type"]


out_file = open(out_file_path, "w+")

json.dump(cs, out_file, separators=(',', ':'))
