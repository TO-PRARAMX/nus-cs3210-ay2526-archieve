# Some important remarks

Make sure to supply `--input=0` to `srun` when forwarding input.

```bash
srun -N1 -n4 --input=0 ./engine < inputs/input1.in  > OUT_MINE
```


To test the code, run

```python3
python3 scripts/unit_test.py
```
