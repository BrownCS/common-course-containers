## CCC New User Workflow/Map -- Current Code

Assuming a brand new student, who knows nothing but what is given in the README, this is what the workflow looks like (somewhat detailed technical connections)

### Step 1. ./install.sh

--> sets up initial variables and paths:

    - VERSION, SCRIPT_NAME, REPO_DIR, INSTALL_MODE, BIN_DIR, SHARE_DIR, SEARCH_PATH, MAIN_SCRIPT

--> checks installation permissions (like system vs user, not having sudo when you need it, or using root when unnecessary)

--> checks, in order, for these dependencies: Podman and Git

--> validates existence of ccc.sh, registry.sh, Dockerfile.template, "VERSION" and "share" directory

--> copies all .sh files from /share to $SHARE_DIR for Docker setup

--> sets $PATH variable to include ~/.local/bin so CCC commands can be found

#### Main Importance:

--> Validation + Dependency checks to catch early bugs

--> Copies files to stable locations: BIN_DIR = ~/.local/bin, SHARE_DIR = ~/.local/share/ccc. These are important for stable image building (stable reference)

#### Questions

1. Could we run CCC commands without running ./install.sh first? --> yes, but the stable paths help support deterministic behavior

2. Do we really need different install modes? It defaults to user mode, and I'm not sure why/when one would use system mode.

3. If we are already running on a Linux machine, we don't really need Podman. Do we need to require this as a dependency from the jump?

4. Ultimately, given the questions above, does this really need to be a separate file? Might need to rework this a bit.

#### Files/Dependencies

--> install.sh, share/utils.sh



### Step 2. ccc init

--> First routes to ccc.sh, which sets SCRIPT_DIR, load util functions, checks to see that user is in HOST_MODE, this loads share/courses.sh, share/container.sh, share/runtime.sh, and share/hostmode.sh.

--> calls `host_main init`, which routes to host_mode.sh

--> host_main routes to init_courses_dir, which creates courses directory ((pwd)/courses) and uses util functions to save directory and set settings

#### Main Importance: 

--> Sets up course directory

#### Questions:

1. Why do we need to load share/courses.sh, share/container.sh, and share/runtime.sh if we don't use them? it seems a bit overkill.

2. With that, could this be compressed into the ./install.sh function? do these even need to be a separate function at all, and just run automatically (without explicit user command)?

#### Files/Dependencies

--> ccc.sh, share/host_mode.sh, share/utils.sh (unused, but loaded, share/courses.sh, share/container.sh, and share/runtime.sh)



### Step 3. ccc setup [course name]

--> First routes to ccc.sh again, which re-sets SCRIPT_DIR, re-loads util functions, checks to see that user is in HOST_MODE, this re-loads share/courses.sh, share/container.sh, share/runtime.sh, and share/hostmode.sh.

--> calls `host_main setup [course]`, which routes to host_mode.sh

--> host_main first calls local `validate_course` which checks to see if `[course]` is in registry.csv via `get_course_url` in courses.sh

--> then it calls `clone_course` in courses.sh, which performs either a git clone or git pull on the course's corresponding repo url. This notably calls `add_course_context` to add CCC_EXPECTED_COURSE to course/.envrc

--> then it calls `enter_course` in runtime.sh, which creates or enters running container (is beefy, will detail more thoroughly)
    
    --> gets image from courses.sh: get_course_base_image

    --> build_course_image calls build_image in container.sh

    --> Sets up start/run command:
    if $run_setup && [[ "$course" != "default" ]] && [[ -f "$VOLUME_PATH/$course/setup.sh" ]]; then
    startup_cmd="cd '$course_workdir' && sudo apt-get update -y && sudo bash setup.sh"
    fi

    --> checks to see if there is a container for this course already. if so, checks to see if it is running (starts if not running), and then executes start/run command 

    --> If not, calls start_new_container "$startup_cmd" in container.sh, which has the same effect, just creates a new container.

#### Main Importance

--> ensures container for specific course is set up and running

--> clones course repo into courses/[course]

--> adds some course context to course/.envrc (CCC_EXPECT_COURSE) which is used in course container setup.


#### Questions

1. To my understanding, this actually starts and sets up a specific course in a container. What is the point of a subsequent `ccc run [course]` call then? The README is misleading.

2. What exactly does container mode's ccc setup do?  if the host_mode version starts the container, why can't we just merge the two


#### Files/Dependencies

--> ccc.sh, share/host_mode.sh, share/utils.sh, share/courses.sh, share/container.sh, and share/runtime.sh. registry.csv, Dockerfile.template



### Step 4. ccc run [course name]

--> First routes to ccc.sh again, which re-sets SCRIPT_DIR, re-loads util functions, checks to see that user is in HOST_MODE, this re-loads share/courses.sh, share/container.sh, share/runtime.sh, and share/hostmode.sh.

--> calls `host_main run [course]`, which routes to host_mode.sh

--> host_main first calls local `validate_course` which checks to see if `[course]` is in registry.csv via `get_course_url` in courses.sh

--> then it calls `enter_course` in runtime.sh, which creates or enters running container (is beefy, will detail more thoroughly)
    
    --> gets image from courses.sh: get_course_base_image

    --> build_course_image calls build_image in container.sh

    --> checks to see if there is a container for this course already. if so, checks to see if it is running (starts if not running), and then executes start/run command 

    --> If not, calls start_new_container "$startup_cmd" in container.sh, which has the same effect, just creates a new container.

#### Main Importance

--> runs container for specific course

#### Questions

1. As mentioned earlier, I don't fully understand why we have two separate run and setup commands if they ultimately do the same thing.


#### Files/Dependencies

--> ccc.sh, share/host_mode.sh, share/utils.sh, share/courses.sh, share/container.sh, and share/runtime.sh. registry.csv, Dockerfile.template


### Additional Commands:

#### ccc list

This command routes to list_courses in courses.sh which prints all of the courses/sub directories, their repository links, and their commit hash found in the local courses directory (loaded via courses_dir="$(get_base_dir)")

#### ccc update [course] 

This command routes to upgrade_course in course.sh, which effective calls `git pull` on the desired course to update the corresponding local repo



#### ccc clean [target]

This command routes to any combination of these three commands in container.sh: remove_containers, remove_image, remove_network. These call docker/podman commands to remove/delete containers, images, and networks

#### ccc status

This command routes to status.sh. Running `ccc status` shows the default container and which courses use it. Running `ccc status <course>` shows the repo checkout, image, and container state for that course.

#### ccc config

This command is very lightweight and lives in host_mode.sh. It shows the current course directory and config file path, or tells you to run ccc init if those haven't been set up yet. if passed in with -set-courses-dir flag, it allows you to reset the courses directory. NOTE: THIS DOES NOT COPY OVER CONTENTS OF FORMER COURSES DIRECTORY, it just creates a new, empty one.

#### ccc upgrade

This command routes to update_self in  utils.sh, which checks to see if the local version of the ccc repo is older than the most recent version. If so, it curl/wgets the new install.sh file and executes it. NOTE: I THINK THIS NEEDS TO BE FIXED. there should probably be a git pull involved in order to properly update the codebase. or, it should also copy over ccc.sh, registry.csv, maybe even /lib. will look further into this



### Examining container mode commands/paths a little more closely

- ccc list, update, and upgrade are literally exactly the same as host_mode, just called from within the container
- ccc setup calls setup_course in courses.sh. This function, in order does the following:
    1. git clones or pulls the repo for the course
    2. sudo apt update and then run setup.sh for that course, installing/updating necessary packages and dependencies for that course
- ccc run executes handle_container_switching in courses.sh, which basically just prints a message saying you can't switch containers from container mode and that you need to go back to host mode to do so



#

## Revised CCC Goals and Code Architecture

### Packaging 

### 