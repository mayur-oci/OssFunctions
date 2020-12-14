package io.fnproject.kafkaconnect.sink;

import java.net.URL;
import java.net.URLClassLoader;
import java.util.List;

/**
 * A parent-last classloader that will try the child classloader first and then the parent.
 * This takes a fair bit of doing because java really prefers parent-first.
 * <p>
 * For those not familiar with class loading trickery, be wary
 */
class ParentLastUrlClassLoader extends ClassLoader {
    private ChildUrlClassLoader childClassLoader;

    public ParentLastUrlClassLoader(List<URL> classpath) {
        super(Thread.currentThread().getContextClassLoader());

//        if(Thread.currentThread().getContextClassLoader() == this.getClass().getClassLoader()){
//            System.out.println("same classloaders for thread and parent one");
//        }

        URL[] urls = classpath.toArray(new URL[classpath.size()]);
        System.out.println("urls = " + urls);
        childClassLoader = new ChildUrlClassLoader(urls, new FindClassClassLoader(this.getParent()));
    }

    @Override
    protected synchronized Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
        try {
            // first we try to find a class inside the child classloader
            Class<?> clsCls = childClassLoader.findClass(name);
            System.out.println("Loaded class in custom cl: " + clsCls.getCanonicalName());
            return clsCls;
        } catch (ClassNotFoundException e) {
            // didn't find it, try the parent
            return super.loadClass(name, resolve);
        }
    }

    /**
     * This class allows me to call findClass on a classloader
     */
    private static class FindClassClassLoader extends ClassLoader {
        public FindClassClassLoader(ClassLoader parent) {
            super(parent);
        }

        @Override
        public Class<?> findClass(String name) throws ClassNotFoundException {
            return super.findClass(name);
        }
    }

    /**
     * This class delegates (child then parent) for the findClass method for a URLClassLoader.
     * We need this because findClass is protected in URLClassLoader
     */
    private static class ChildUrlClassLoader extends URLClassLoader {
        private FindClassClassLoader realParent;

        public ChildUrlClassLoader(URL[] urls, FindClassClassLoader realParent) {
            super(urls, null);

            this.realParent = realParent;
        }

        @Override
        public Class<?> findClass(String name) throws ClassNotFoundException {
            try {
                // first try to use the URLClassLoader findClass
                //System.out.println("Class name being loaded by ccl is : "+ name);
                //System.out.println( " and it set of urls is :"+this.getURLs()[0]);
                Class<?> findAlreadyLoaded = this.findLoadedClass(name);
                if (findAlreadyLoaded == null)
                    return super.findClass(name);
                else
                    return findAlreadyLoaded;
            } catch (ClassNotFoundException e) {
                // if that fails, we ask our real parent classloader to load the class (we give up)
                return realParent.loadClass(name);
            }
        }
    }
}
