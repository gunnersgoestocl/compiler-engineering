# compiler-engineering
For the purpose of knowledge sharing and hands-on experience on compiler implementation and design.

## Write a knowledge sharing

- Build
```bash
cd knowledge_sharing
bash ./mk_template.sh 0X_TITLE
```
- Compile
```bash
cd knowledge_sharing
bash ./watch.sh 0X_TITLE
```

## To add your own project
- add your own repository as a submodule
```bash
git submodule add git@github.com:gunnersgoestocl/miniLLVM.git ./YOURNAME
```

- update
```bash
git submodule update --remote
git add ${YOURNAME}
git commit -m "sync ${YOURNAME} submodule"
```