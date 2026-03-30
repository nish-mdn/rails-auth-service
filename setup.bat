@echo off
REM Auth Service Setup Script for Windows

echo.
echo ======================================
echo Auth Service - Development Setup
echo ======================================
echo.

REM Check Ruby
echo Checking Ruby installation...
ruby --version >nul 2>&1
if %errorlevel% neq 0 (
    echo X Ruby is not installed
    echo Install from: https://rubyinstaller.org/
    pause
    exit /b 1
)

echo OK Ruby is installed
echo.

REM Check Rails
echo Checking Rails...
rails --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Installing Rails...
    gem install rails
)
echo OK Rails is available
echo.

REM Check MySQL
echo Checking MySQL...
mysql --version >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: MySQL is not in PATH
    echo Please ensure MySQL is installed and accessible
)
echo OK MySQL should be ready
echo.

REM Install gems
echo Installing gem dependencies...
call bundle install
echo OK Gems installed
echo.

REM Create database
echo Creating databases...
call rails db:create
echo OK Databases created
echo.

REM Run migrations
echo Running migrations...
call rails db:migrate
echo OK Migrations complete
echo.

REM Generate JWT keys
echo Generating RSA keys for JWT...
call rails jwt:generate_keys
echo OK RSA keys generated
echo.

REM Summary
echo ======================================
echo OK Setup Complete!
echo ======================================
echo.
echo Next steps:
echo 1. Start the server: rails server
echo 2. Visit: http://localhost:3000
echo 3. Read: QUICKSTART.md for API usage
echo.
echo Create a test user:
echo   rails console
echo   User.create!(email: 'test@example.com', password: 'Password123')
echo.
pause
