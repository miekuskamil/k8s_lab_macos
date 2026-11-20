# Level 1: Foundations

These modules teach the basics that every later module builds on, in six domains. The first five follow an application from its image to the network, and they run on the [practice cluster](../practice-cluster.md) with the application extras, as timed tasks that the [timed tasks page](../timed-tasks.md) explains. The sixth teaches the service mesh on the k3d lab, which module 0 checks before it installs `istioctl`. The two halves don't depend on each other, so take them in either order or side by side.

## Building and running applications

- [Module 33: Building and running applications](33-building-and-running-applications.md)

## Deploying and updating applications

- [Module 34: Deploying and updating applications](34-deploying-and-updating-applications.md)

## Observing and debugging applications

- [Module 35: Observing and debugging applications](35-observing-and-debugging-applications.md)

## Configuration and secrets

- [Module 36: Configuration and secrets](36-configuration-and-secrets.md)

## Services and networking

- [Module 37: Services and networking](37-services-and-networking.md)

Take modules 33 to 37 in order, because each one uses the objects of the one before, and module 37 relies on the readiness probes of module 35.

## Service mesh basics

- [Module 0: Setup](00-setup.md)
- [Module 1: What a mesh adds](01-what-a-mesh-adds.md)
- [Module 2: Identity and mTLS](02-identity-and-mtls.md)
- [Module 3: Authorization](03-authorization.md)
- [Module 4: Traffic routing](04-traffic-routing.md)
- [Module 5: Resilience](05-resilience.md)
- [Module 6: Observability](06-observability.md)
- [Module 8: Incidents](08-incidents.md)
- [Module 9: Command reference](09-command-reference.md)
- [Module 29: The life of a request](29-life-of-a-request.md)

Take the mesh modules in order, read module 29 after module 7 to tie the pieces together, and finish with module 8 to test yourself. Module 9 is a reference to keep open while you work.

## Timed practice exams

- [Timed practice exam 1: applications, one topic per task](practice-exam-1.md)
- [Timed practice exam 2: applications, broken things to repair](practice-exam-2.md)
- [Timed practice exam 3: applications, several objects per task](practice-exam-3.md)

Each exam covers modules 33 to 37 with a 2-hour clock and runs on the practice cluster: `./platform-engineering/practice-exam.sh setup 1` starts exam 1, and `score 1` scores it.

The [course overview](../README.md) shows the routes through all four levels and the recommended order.
