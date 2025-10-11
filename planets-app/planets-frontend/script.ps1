docker build -t planets-web-app .

docker run -p 8090:80 planets-web-app

docker tag planets-web-app daradu/planets-web-app:latest
docker push daradu/planets-web-app:latest

docker login

docker push daradu/planets-web-app:latest

kubectl apply -f planets-web-app-dep.yaml
kubectl apply -f planets-web-app-svc.yaml

# kubectl delete -f planets-web-app-dep.yaml
# kubectl delete -f planets-web-app-svc.yaml

kubectl apply -f manifest.yaml